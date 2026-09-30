begin;
set local role service_role;
do $$
declare u uuid; rid uuid; address text:=gen_random_uuid()::text||'@example.invalid'; own text:='p_'||replace(gen_random_uuid()::text,'-',''); other text:='p_'||replace(gen_random_uuid()::text,'-',''); denied boolean:=false;
begin
 select id into u from atmeet_fahu.admin_accounts where role='admin' limit 1;
 if u is null then raise exception 'Admin fixture required';end if;
 perform atmeet_fahu.meeting_request_account('Fixture',address,'Test');
 perform atmeet_fahu.meeting_request_account('Duplicate',address,'Test');
 if (select count(*) from atmeet_fahu.meeting_account_requests where email=address)<>1 then raise exception 'Duplicate request';end if;
 select id into rid from atmeet_fahu.meeting_account_requests where email=address;
 update atmeet_fahu.admin_accounts set role='manager' where id=u;
 begin perform atmeet_fahu.meeting_review_request(u,rid,'approve','admin',repeat('a',64)); exception when others then denied:=true;end;
 if not denied then raise exception 'Manager approved request';end if;
 insert into atmeet_fahu.polls(id,data) values(own,jsonb_build_object('ownerId',u)::text),(other,jsonb_build_object('ownerId',gen_random_uuid())::text);
 insert into atmeet_fahu.votes(id,poll_id,edit_hash,data) values(own,own,'fixture','{}');
 if atmeet_fahu.meeting_account_delete_poll(u,other) then raise exception 'Foreign deletion allowed';end if;
 if not atmeet_fahu.meeting_account_delete_poll(u,own) then raise exception 'Own deletion denied';end if;
 if exists(select 1 from atmeet_fahu.votes where poll_id=own) then raise exception 'Orphan votes';end if;
 update atmeet_fahu.admin_accounts set role='admin' where id=u;
 if atmeet_fahu.meeting_review_request(u,rid,'approve','manager',repeat('a',64)) is null then raise exception 'Approval failed';end if;
 if not exists(select 1 from atmeet_fahu.meeting_admin_invitations where email=address and role='manager') then raise exception 'Invitation role incorrect';end if;
 if atmeet_fahu.meeting_review_request(u,rid,'approve','admin',repeat('b',64)) is not null then raise exception 'Double approval';end if;
 if not atmeet_fahu.meeting_account_delete_poll(u,other) then raise exception 'Admin deletion denied';end if;
end $$;
rollback;
select 'PASS: service_role duplicate prevention, admin approval, assigned role, manager own-only deletion, dependent votes; rolled back' as result;
