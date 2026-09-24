import {scrypt as derive,randomBytes,timingSafeEqual} from 'node:crypto';
const scrypt=(password:string,salt:string)=>new Promise<Buffer>((resolve,reject)=>derive(password,salt,64,{N:32768,r:8,p:3,maxmem:64*1024*1024},(error,key)=>error?reject(error):resolve(key)));
export async function passwordHash(password:string){const salt=randomBytes(16).toString('hex');const key=await scrypt(password,salt) as Buffer;return `scrypt-v1$${salt}$${key.toString('hex')}`;}
export async function passwordMatches(password:string,stored:string){const [kind,salt,hex]=stored.split('$');if(kind!=='scrypt-v1'||!/^[a-f0-9]{32}$/.test(salt||'')||!/^[a-f0-9]{128}$/.test(hex||''))return false;const key=await scrypt(password,salt) as Buffer;return timingSafeEqual(key,Buffer.from(hex,'hex'));}
