-- Additive account roles and schedule extension. Only atmeet_fahu application objects.
begin;
alter table atmeet_fahu.meeting_admin_invitations add column role text not null default 'admin' check(role in ('admin','manager'));
alter table atmeet_fahu.admin_accounts add column role text not null default 'admin' check(role in ('admin','manager'));
create function atmeet_fahu.meeting_account_role(p_user uuid) returns text language sql stable security invoker set search_path='' as $$ select role from atmeet_fahu.admin_accounts where id=p_user and active; $$;
create index meeting_polls_owner on atmeet_fahu.polls ((data::jsonb->>'ownerId'));
create function atmeet_fahu.meeting_account_history(p_user uuid,p_offset integer default 0,p_search text default '') returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare r text; result jsonb;
begin
 r:=atmeet_fahu.meeting_account_role(p_user); if r is null then raise exception 'Forbidden'; end if;
 with allowed as (select p.* from atmeet_fahu.polls p where (r='admin' or p.data::jsonb->>'ownerId'=p_user::text) and strpos(lower(p.data::jsonb->>'title'),lower(left(p_search,120)))>0),
 page as (select * from allowed order by data::jsonb->>'created' desc,id desc limit 25 offset greatest(p_offset,0))
 select jsonb_build_object('total',(select count(*) from allowed),'polls',coalesce((select jsonb_agg(jsonb_build_object('poll',p.data::jsonb-'manageHash','responseCount',(select count(*) from atmeet_fahu.votes v where v.poll_id=p.id)) order by p.data::jsonb->>'created' desc,p.id desc) from page p),'[]'::jsonb)) into result;
 return result;
end $$;
create function atmeet_fahu.meeting_extend_poll(p_user uuid,p_id text,p_revision integer,p_patch jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare r text; old jsonb; updated jsonb;
begin
 r:=atmeet_fahu.meeting_account_role(p_user); if r is null then raise exception 'Forbidden'; end if;
 select data::jsonb into old from atmeet_fahu.polls where id=p_id for update;
 if old is null or (r<>'admin' and coalesce(old->>'ownerId','')<>p_user::text) then return null; end if;
 if coalesce((old->>'scheduleRevision')::integer,0)<>p_revision then raise exception 'Schedule changed'; end if;
 if exists(select 1 from jsonb_object_keys(p_patch) as k where k not in ('start','end','from','to','dailyRanges')) then raise exception 'Invalid patch'; end if;
 updated:=old||p_patch||jsonb_build_object('scheduleRevision',p_revision+1,'updated',now());
 update atmeet_fahu.polls set data=updated::text where id=p_id;
 return updated-'manageHash';
end $$;
create or replace function atmeet_fahu.admin_accept_invitation(p_hash text,p_email text,p_password_hash text)
returns setof atmeet_fahu.admin_accounts language plpgsql security invoker set search_path='' as $$
declare recipient text; selected_role text;
begin
 select email,role into recipient,selected_role from atmeet_fahu.meeting_admin_invitations where token_hash=p_hash and used_at is null and expires_at>now() for update;
 if recipient is null or recipient<>lower(trim(p_email)) then return; end if;
 insert into atmeet_fahu.admin_accounts(email,password_hash,role) values(recipient,p_password_hash,selected_role) on conflict(email) do nothing;
 if not found then return; end if;
 update atmeet_fahu.meeting_admin_invitations set used_at=now() where token_hash=p_hash;
 return query select * from atmeet_fahu.admin_accounts where email=recipient;
end $$;
revoke execute on function atmeet_fahu.meeting_account_role(uuid),atmeet_fahu.meeting_account_history(uuid,integer,text),atmeet_fahu.meeting_extend_poll(uuid,text,integer,jsonb) from public,anon,authenticated;
grant execute on function atmeet_fahu.meeting_account_role(uuid),atmeet_fahu.meeting_account_history(uuid,integer,text),atmeet_fahu.meeting_extend_poll(uuid,text,integer,jsonb) to service_role;
commit;
