begin;
set local role service_role;
do $$
declare uid uuid; own text:='p_'||replace(gen_random_uuid()::text,'-','');foreign_id text:='p_'||replace(gen_random_uuid()::text,'-','');d jsonb;result jsonb;before_votes text;
begin
 select id into uid from atmeet_fahu.admin_accounts where role='admin' and active limit 1;
 if uid is null then raise exception 'Existing admin needed';end if;
 update atmeet_fahu.admin_accounts set role='manager' where id=uid;
 d:=jsonb_build_object('id',own,'title','Rollback reopen test','ownerId',uid,'mode','dates','start','2026-10-01','end','2026-10-01','from',540,'to',660,'step',60,'duration',60,'timezone','America/Santiago','created',now(),'closed',true,'closedAt',now(),'selectedSlot','2026-10-01@540','selectedDate','2026-10-01','scheduleRevision',2);
 insert into atmeet_fahu.polls(id,data) values(own,d::text),(foreign_id,(d||jsonb_build_object('id',foreign_id,'ownerId',gen_random_uuid()))::text);
 insert into atmeet_fahu.votes(id,poll_id,edit_hash,data) values(own,own,'fixture',jsonb_build_object('id',own,'name','Fixture','slots',jsonb_build_object('2026-10-01@540','yes'))::text);
 select data into before_votes from atmeet_fahu.votes where id=own;
 if atmeet_fahu.meeting_account_manage(uid,foreign_id,'reopen') is not null then raise exception 'Foreign manager reopen allowed';end if;
 result:=atmeet_fahu.meeting_account_manage(uid,own,'reopen');
 if result is null or (result->>'closed')::boolean or result?'selectedSlot' or result?'selectedDate' or result?'closedAt' or (result->>'scheduleRevision')::int<>3 then raise exception 'Reopen failed';end if;
 if (select data from atmeet_fahu.votes where id=own)<>before_votes then raise exception 'Responses changed';end if;
 if atmeet_fahu.meeting_account_manage(uid,own,'reopen')<>result then raise exception 'Reopen not idempotent';end if;
 update atmeet_fahu.admin_accounts set role='admin' where id=uid;
 if (atmeet_fahu.meeting_account_manage(uid,foreign_id,'reopen')->>'closed')::boolean then raise exception 'Admin reopen failed';end if;
 if has_function_privilege('anon','atmeet_fahu.meeting_account_manage(uuid,text,text,boolean,text,text)','execute') or has_function_privilege('authenticated','atmeet_fahu.meeting_account_manage(uuid,text,text,boolean,text,text)','execute') then raise exception 'Public execution allowed';end if;
end $$;
select 'PASS: manager own-only, admin all, preserved responses, confirmation cleared, revision, idempotence and service-only access' as result;
rollback;
