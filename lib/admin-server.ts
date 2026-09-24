import {passwordHash,passwordMatches} from './admin-password';
import {z} from 'zod';

const credentials=z.object({email:z.string().email().max(254).transform(v=>v.toLowerCase().trim()),password:z.string().min(1).max(128)});
const inviteToken=z.string().regex(/^[a-f0-9]{64}$/);
const secret=()=>Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join('');
export async function digest(value:string){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value))),b=>b.toString(16).padStart(2,'0')).join('');}
class HttpError extends Error {constructor(public status:number,message:string){super(message);}}
type AdminUser={id:string;email:string;active:boolean;password_hash:string};

export function adminHandler(url:string,key:string,fetcher:typeof fetch=fetch){
  const root=url.replace(/\/$/,'');
  async function call(path:string,method='GET',body?:unknown,bearer=key){
    const r=await fetcher(root+path,{method,headers:{'Accept-Profile':'atmeet_fahu','Content-Profile':'atmeet_fahu',apikey:key,Authorization:`Bearer ${bearer}`,'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)});
    const data=await r.text();
    if(!r.ok)throw new HttpError(r.status>=500?503:400,'No se pudo completar la operación. Revisa los datos e inténtalo nuevamente.');
    return data?JSON.parse(data):null;
  }
  const rest=(path:string,method='GET',body?:unknown)=>call('/rest/v1/'+path,method,body);
  return async function handler(request:Request):Promise<Response>{
    const current=new URL(request.url),secure=current.protocol==='https:',cookieName=secure?'__Host-atmeet-fahu-admin':'atmeet-fahu-admin';
    const responseHeaders=new Headers({'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
    const reply=(data:unknown,status=200)=>Response.json(data,{status,headers:responseHeaders});
    const cookie=(value:string,age:number)=>responseHeaders.append('Set-Cookie',`${cookieName}=${value}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${age}${secure?'; Secure':''}`);
    let issuedSession:string|undefined;
    async function session(user:AdminUser){
      const token=secret();issuedSession=await digest(token);
      await rest('meeting_admin_sessions','POST',{token_hash:issuedSession,user_id:user.id,expires_at:new Date(Date.now()+8*3600000).toISOString()});
      cookie(token,8*3600);
    }
    async function signedIn(){
      const raw=request.headers.get('cookie')?.split(';').map(s=>s.trim()).find(s=>s.startsWith(cookieName+'='))?.slice(cookieName.length+1);
      if(!raw||!inviteToken.safeParse(raw).success)throw new HttpError(401,'Inicia sesión para acceder a la administración.');
      const hash=await digest(raw);
      const rows=await rest(`meeting_admin_sessions?token_hash=eq.${hash}&expires_at=gt.${encodeURIComponent(new Date().toISOString())}&select=user_id`);
      if(!rows?.[0])throw new HttpError(401,'Tu sesión terminó. Vuelve a iniciar sesión.');
      const accounts=await rest(`admin_accounts?id=eq.${encodeURIComponent(rows[0].user_id)}&active=eq.true&select=*`);
      const user:AdminUser=accounts?.[0];
      if(!user)throw new HttpError(403,'Esta cuenta no tiene acceso de administración.');
      return {user,hash};
    }
    try{
      const path=current.pathname.replace(/^\/api\/admin\/?/,'');
      if(request.method!=='GET'){
        if(request.headers.get('origin')!==current.origin)throw new HttpError(403,'Origen no permitido.');
        if(!request.headers.get('content-type')?.includes('application/json'))throw new HttpError(415,'Formato no permitido.');
      }
      let body:unknown={};
      if(request.method==='POST'){
        const raw=await request.text();if(raw.length>12000)throw new HttpError(413,'Solicitud demasiado grande.');
        try{body=JSON.parse(raw);}catch{throw new HttpError(400,'Formato no permitido.');}
      }
      if(path==='login'&&request.method==='POST'){
        const input=credentials.parse(body);
        const allowed=await rest('rpc/admin_login_attempt','POST',{p_email:input.email});
        if(!allowed)throw new HttpError(429,'Demasiados intentos. Espera 15 minutos antes de volver a intentar.');
        const accounts=await rest(`admin_accounts?email=eq.${encodeURIComponent(input.email)}&active=eq.true&select=*`);
        const user:AdminUser=accounts?.[0];
        // Derive a hash even for unknown accounts, so failure timing is comparable.
        const valid=user?await passwordMatches(input.password,user.password_hash):(await passwordHash(input.password),false);
        if(!valid)throw new HttpError(401,'Correo o contraseña incorrectos.');
        await session(user);return reply({email:user.email});
      }
      if(path==='accept'&&request.method==='POST'){
        const input=credentials.extend({token:inviteToken,password:z.string().min(12).max(128)}).parse(body);
        const hash=await digest(input.token);
        const accounts=await rest('rpc/admin_accept_invitation','POST',{p_hash:hash,p_email:input.email,p_password_hash:await passwordHash(input.password)});
        const user:AdminUser=accounts?.[0];
        if(!user)throw new HttpError(400,'La invitación no es válida, ha vencido, fue utilizada o el correo ya tiene una cuenta.');
        await session(user);return reply({email:user.email},201);
      }
      if(path==='logout'&&request.method==='POST'){
        const raw=request.headers.get('cookie')?.split(';').map(s=>s.trim()).find(s=>s.startsWith(cookieName+'='))?.slice(cookieName.length+1);
        if(raw&&inviteToken.safeParse(raw).success)await rest(`meeting_admin_sessions?token_hash=eq.${await digest(raw)}`,'DELETE');
        cookie('',0);return reply({ok:true});
      }
      const {user}=await signedIn();
      if(path==='me'&&request.method==='GET')return reply({email:user.email});
      if(path==='history'&&request.method==='GET'){
        const offset=z.coerce.number().int().min(0).max(1000000).parse(current.searchParams.get('offset')||0);
        const search=z.string().max(120).parse(current.searchParams.get('search')||'');
        return reply(await rest('rpc/meeting_history','POST',{p_offset:offset,p_search:search}));
      }
      if(path==='delete-poll'&&request.method==='POST'){
        const parsed=z.object({id:z.string().regex(/^p_[a-f0-9]{32}$/)}).safeParse(body);
        if(!parsed.success)throw new HttpError(400,'El identificador de la consulta no es válido.');
        const deleted=await rest('rpc/meeting_delete_poll','POST',{p_id:parsed.data.id});
        if(!deleted)throw new HttpError(404,'La consulta ya no existe. Actualiza el historial.');
        return reply({ok:true});
      }
      if(path==='invitations'&&request.method==='POST'){
        const {email}=credentials.pick({email:true}).parse(body),token=secret();
        await rest('meeting_admin_invitations','POST',{token_hash:await digest(token),email,created_by:user.id});
        return reply({url:current.origin+'/admin#invite='+token,expiresInDays:7},201);
      }
      if(path==='password'&&request.method==='POST'){
        const input=z.object({currentPassword:z.string().min(1).max(128),password:z.string().min(12).max(128)}).parse(body);
        if(!await passwordMatches(input.currentPassword,user.password_hash))throw new HttpError(401,'Contraseña actual incorrecta.');
        const changed=await rest('rpc/admin_change_password','POST',{p_id:user.id,p_old_hash:user.password_hash,p_new_hash:await passwordHash(input.password)});
        if(!changed)throw new HttpError(409,'La cuenta cambió. Inicia sesión de nuevo.');
        await session(user);return reply({ok:true});
      }
      return reply({error:'Operación no disponible.'},404);
    }catch(e){
      if(e instanceof z.ZodError)return reply({error:'Revisa el correo y los datos. La nueva contraseña debe tener al menos 12 caracteres.'},400);
      if(e instanceof HttpError)return reply({error:e.message},e.status);
      return reply({error:'No se pudo acceder a la administración. Inténtalo nuevamente.'},503);
    }
  };
}
