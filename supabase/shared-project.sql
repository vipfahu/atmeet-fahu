-- Install only in the chosen shared project. No changes to public or auth.
begin;
create schema atmeet_fahu;
revoke all on schema atmeet_fahu from public, anon, authenticated;
grant usage on schema atmeet_fahu to service_role;
create table atmeet_fahu.admin_accounts (
 id uuid primary key default gen_random_uuid(),
 email text not null unique check(email=lower(trim(email))),
 password_hash text not null,
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table atmeet_fahu.admin_login_limits(email text primary key, attempts integer not null, window_start timestamptz not null);
-- Ejecutar una vez en el proyecto Supabase elegido.
create table atmeet_fahu.polls (id text primary key, data text not null);
create table atmeet_fahu.votes (id text primary key, poll_id text not null references atmeet_fahu.polls(id), edit_hash text not null, data text not null);
create index idx_votes_poll on atmeet_fahu.votes(poll_id);
alter table atmeet_fahu.polls enable row level security;
alter table atmeet_fahu.votes enable row level security;
-- Sin políticas públicas. Solo las funciones de servidor usan service_role.
revoke all on atmeet_fahu.polls, atmeet_fahu.votes from public, anon, authenticated;

grant select, insert, update, delete on atmeet_fahu.polls, atmeet_fahu.votes to service_role;

-- Administración por invitación. Ejecutar después de schema.sql.
create table if not exists atmeet_fahu.meeting_admin_invitations (
  token_hash text primary key,
  email text not null,
  created_by uuid references atmeet_fahu.admin_accounts(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days',
  used_at timestamptz,
  claim_id uuid
);
create index if not exists meeting_invites_creator on atmeet_fahu.meeting_admin_invitations(created_by);
create table if not exists atmeet_fahu.meeting_admin_sessions (
  token_hash text primary key,
  user_id uuid not null references atmeet_fahu.admin_accounts(id) on delete cascade,
  expires_at timestamptz not null default now() + interval '8 hours'
);
create index if not exists meeting_sessions_user on atmeet_fahu.meeting_admin_sessions(user_id);
alter table atmeet_fahu.meeting_admin_invitations enable row level security;
alter table atmeet_fahu.meeting_admin_sessions enable row level security;
revoke all on atmeet_fahu.meeting_admin_invitations, atmeet_fahu.meeting_admin_sessions from public, anon, authenticated;
grant select, insert, update, delete on atmeet_fahu.meeting_admin_invitations, atmeet_fahu.meeting_admin_sessions to service_role;
create index if not exists meeting_polls_created on atmeet_fahu.polls ((data::jsonb->>'created') desc, id desc);

create or replace function atmeet_fahu.meeting_history(p_offset integer default 0, p_search text default '')
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object(
    'total', (select count(*) from atmeet_fahu.polls where strpos(lower(data::jsonb->>'title'),lower(left(p_search,120)))>0),
    'polls', coalesce((select jsonb_agg(x.item order by x.created desc,x.id desc) from (
      select p.id, p.data::jsonb->>'created' as created,
        jsonb_build_object('poll',p.data::jsonb,'responseCount',(select count(*) from atmeet_fahu.votes v where v.poll_id=p.id)) as item
      from atmeet_fahu.polls p
      where strpos(lower(p.data::jsonb->>'title'),lower(left(p_search,120)))>0
      order by p.data::jsonb->>'created' desc,p.id desc
      limit 25 offset greatest(p_offset,0)
    ) x),'[]'::jsonb)
  );
$$;
revoke all on function atmeet_fahu.meeting_history(integer,text) from public, anon, authenticated;
grant execute on function atmeet_fahu.meeting_history(integer,text) to service_role;

-- El borrado es atómico y solo está disponible para las funciones del servidor.
create or replace function atmeet_fahu.meeting_delete_poll(p_id text)
returns boolean language plpgsql security invoker set search_path = '' as $$
begin
  if p_id !~ '^p_[a-f0-9]{32}$' then
    raise exception 'Identificador inválido';
  end if;
  perform 1 from atmeet_fahu.polls where id=p_id for update;
  if not found then return false; end if;
  delete from atmeet_fahu.votes where poll_id=p_id;
  delete from atmeet_fahu.polls where id=p_id;
  return true;
end;
$$;
revoke all on function atmeet_fahu.meeting_delete_poll(text) from public, anon, authenticated;
grant execute on function atmeet_fahu.meeting_delete_poll(text) to service_role;

-- Server-only operations; serialize closure and response writes on the poll row.
create or replace function atmeet_fahu.meeting_save_vote(p_id text,p_poll_id text,p_edit_hash text,p_data text)
returns boolean language plpgsql security invoker set search_path='' as $$
declare document jsonb;
begin
 select data::jsonb into document from atmeet_fahu.polls where id=p_poll_id for update;
 if document is null or coalesce((document->>'closed')::boolean,false) then return false; end if;
 if not exists(select 1 from atmeet_fahu.votes where id=p_id) and (select count(*) from atmeet_fahu.votes where poll_id=p_poll_id)>=200 then return false; end if;
 insert into atmeet_fahu.votes(id,poll_id,edit_hash,data) values(p_id,p_poll_id,p_edit_hash,p_data)
 on conflict(id) do update set data=excluded.data where votes.edit_hash=excluded.edit_hash and votes.poll_id=excluded.poll_id;
 return found;
end $$;
create or replace function atmeet_fahu.meeting_manage_poll(p_id text,p_hash text,p_action text,p_notify boolean default null)
returns text language plpgsql security invoker set search_path='' as $$
declare document jsonb;
begin
 select data::jsonb into document from atmeet_fahu.polls where id=p_id for update;
 if document is null or document->>'manageHash' is distinct from p_hash then return null; end if;
 if p_action='close' then document=document||jsonb_build_object('closed',true,'closedAt',coalesce(document->>'closedAt',to_char(now() at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
 elsif p_action='notifications' and p_notify is not null then document=jsonb_set(document,'{creator,notify}',to_jsonb(p_notify));
 else return null; end if;
 update atmeet_fahu.polls set data=document::text where id=p_id;
 return document::text;
end $$;
create or replace function atmeet_fahu.meeting_creator_access(p_id text,p_hash text)
returns boolean language plpgsql security invoker set search_path='' as $$
declare document jsonb;
begin
 select data::jsonb into document from atmeet_fahu.polls where id=p_id for update;
 if document is null or document#>>'{creator,email}' is null then return false; end if;
 if document->>'accessRequestedAt' is not null and (document->>'accessRequestedAt')::timestamptz>now()-interval '5 minutes' then return false; end if;
 update atmeet_fahu.polls set data=(document||jsonb_build_object('manageHash',p_hash,'accessRequestedAt',now()))::text where id=p_id;
 return true;
end $$;
revoke all on function atmeet_fahu.meeting_save_vote(text,text,text,text),atmeet_fahu.meeting_manage_poll(text,text,text,boolean),atmeet_fahu.meeting_creator_access(text,text) from public,anon,authenticated;
grant execute on function atmeet_fahu.meeting_save_vote(text,text,text,text),atmeet_fahu.meeting_manage_poll(text,text,text,boolean),atmeet_fahu.meeting_creator_access(text,text) to service_role;


create function atmeet_fahu.admin_login_attempt(p_email text) returns boolean language plpgsql security invoker set search_path='' as $$
declare n integer;
begin
 insert into atmeet_fahu.admin_login_limits(email,attempts,window_start) values(lower(trim(p_email)),1,now())
 on conflict(email) do update set
 attempts=case when admin_login_limits.window_start < now()-interval '15 minutes' then 1 else admin_login_limits.attempts+1 end,
 window_start=case when admin_login_limits.window_start < now()-interval '15 minutes' then now() else admin_login_limits.window_start end
 returning attempts into n;
 return n<=8;
end $$;
create function atmeet_fahu.admin_accept_invitation(p_hash text,p_email text,p_password_hash text)
returns setof atmeet_fahu.admin_accounts language plpgsql security invoker set search_path='' as $$
declare recipient text;
begin
 select email into recipient from atmeet_fahu.meeting_admin_invitations where token_hash=p_hash and used_at is null and expires_at>now() for update;
 if recipient is null or recipient<>lower(trim(p_email)) then return; end if;
 if exists(select 1 from atmeet_fahu.admin_accounts where email=recipient) then return; end if;
 insert into atmeet_fahu.admin_accounts(email,password_hash) values(recipient,p_password_hash) on conflict(email) do nothing;
 if not found then return; end if;
 update atmeet_fahu.meeting_admin_invitations set used_at=now() where token_hash=p_hash;
 return query select * from atmeet_fahu.admin_accounts where email=recipient;
end $$;
create function atmeet_fahu.admin_change_password(p_id uuid,p_old_hash text,p_new_hash text)
returns boolean language plpgsql security invoker set search_path='' as $$
begin
 update atmeet_fahu.admin_accounts set password_hash=p_new_hash where id=p_id and password_hash=p_old_hash and active;
 if not found then return false; end if;
 delete from atmeet_fahu.meeting_admin_sessions where user_id=p_id;
 return true;
end $$;
alter table atmeet_fahu.admin_accounts enable row level security;
alter table atmeet_fahu.admin_login_limits enable row level security;
revoke all on all tables in schema atmeet_fahu from public,anon,authenticated;
grant select,insert,update,delete on all tables in schema atmeet_fahu to service_role;
revoke execute on all functions in schema atmeet_fahu from public,anon,authenticated;
grant execute on all functions in schema atmeet_fahu to service_role;
-- Keep future objects private too.
alter default privileges in schema atmeet_fahu revoke all on tables from public,anon,authenticated;
alter default privileges in schema atmeet_fahu revoke execute on functions from public,anon,authenticated;
commit;
