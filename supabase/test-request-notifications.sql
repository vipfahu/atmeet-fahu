begin;
set local role service_role;
insert into atmeet_fahu.meeting_account_requests(name,email) values('SQL notice validation','notice-test-'||gen_random_uuid()::text||'@example.invalid');
do $$ declare r jsonb; c uuid:=gen_random_uuid(); e text;
begin
 select email into e from atmeet_fahu.meeting_account_requests where name='SQL notice validation';
 r:=atmeet_fahu.meeting_claim_request_notice(e,c);
 if r is null then raise exception 'claim missing';end if;
 if atmeet_fahu.meeting_claim_request_notice(e,gen_random_uuid()) is not null then raise exception 'duplicate claim';end if;
 perform atmeet_fahu.meeting_ack_request_notice((r->>'id')::uuid,c,'admin@example.invalid',false);
 perform atmeet_fahu.meeting_ack_request_notice((r->>'id')::uuid,c,null,true);
 if atmeet_fahu.meeting_claim_request_notice(e,gen_random_uuid()) is not null then raise exception 'completed replay';end if;
end $$;
select 'PASS: service-role claim, lease, acknowledgment and completed deduplication' as result;
rollback;
