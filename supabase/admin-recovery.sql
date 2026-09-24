-- Additive update for at meet FAHU only; no changes to public or auth.
begin;
create table atmeet_fahu.admin_password_resets (
 user_id uuid primary key references atmeet_fahu.admin_accounts(id) on delete cascade,
 token_hash text not null unique check(token_hash ~ '^[a-f0-9]{64}$'),
 password_snapshot text not null,
 issued_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '30 minutes'
);
alter table atmeet_fahu.admin_password_resets enable row level security;
revoke all on atmeet_fahu.admin_password_resets from public,anon,authenticated;
grant select,insert,update,delete on atmeet_fahu.admin_password_resets to service_role;
create function atmeet_fahu.admin_issue_reset(p_email text,p_hash text) returns boolean
language plpgsql security invoker set search_path='' as $$
declare a atmeet_fahu.admin_accounts;
begin
 select * into a from atmeet_fahu.admin_accounts where email=lower(trim(p_email)) and active for update;
 if not found then return false; end if;
 if exists(select 1 from atmeet_fahu.admin_password_resets where user_id=a.id and issued_at>now()-interval '60 seconds') then return false; end if;
 insert into atmeet_fahu.admin_password_resets(user_id,token_hash,password_snapshot)
 values(a.id,p_hash,a.password_hash) on conflict(user_id) do update
 set token_hash=excluded.token_hash,password_snapshot=excluded.password_snapshot,issued_at=now(),expires_at=now()+interval '30 minutes';
 return true;
end $$;
create function atmeet_fahu.admin_reset_password(p_hash text,p_new_hash text) returns boolean
language plpgsql security invoker set search_path='' as $$
declare uid uuid; a atmeet_fahu.admin_accounts; r atmeet_fahu.admin_password_resets;
begin
 select user_id into uid from atmeet_fahu.admin_password_resets where token_hash=p_hash;
 if uid is null then return false; end if;
 select * into a from atmeet_fahu.admin_accounts where id=uid and active for update;
 if not found then return false; end if;
 select * into r from atmeet_fahu.admin_password_resets where user_id=uid and token_hash=p_hash and expires_at>now() for update;
 if not found or r.password_snapshot<>a.password_hash then return false; end if;
 update atmeet_fahu.admin_accounts set password_hash=p_new_hash where id=uid;
 delete from atmeet_fahu.meeting_admin_sessions where user_id=uid;
 delete from atmeet_fahu.admin_password_resets where user_id=uid;
 return true;
end $$;
revoke execute on function atmeet_fahu.admin_issue_reset(text,text),atmeet_fahu.admin_reset_password(text,text) from public,anon,authenticated;
grant execute on function atmeet_fahu.admin_issue_reset(text,text),atmeet_fahu.admin_reset_password(text,text) to service_role;
commit;
