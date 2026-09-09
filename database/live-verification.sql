begin;
do $$
declare u uuid:=gen_random_uuid();t uuid:=gen_random_uuid();p uuid;s uuid;pi uuid;j jsonb;rid uuid:=gen_random_uuid();begin
 insert into auth.users(id,email) values(u,'verification-'||u::text||'@example.invalid');
 insert into public.pharmacy_tenants(id,name,owner,expires) values(t,'Verification','Verification','2099-01-01');
 insert into public.pharmacy_members(id,name,email,role,tenant_id) values(u,'Verification','verification@example.invalid','owner',t);
 perform set_config('request.jwt.claim.sub',u::text,true);
 execute 'set local role authenticated';
 j:=public.pharmacy_command('product','{"name":"Verification","scientific":"","barcode":"","category":"Test","form":"tablet","strength":"","manufacturer":"","country":"","location":"","carton_boxes":20,"box_strips":3,"strip_units":10,"base_unit":"tablet","sell_unit":250,"sell_strip":2500,"sell_box":7000,"sell_carton":130000,"min_stock":10,"notes":""}',gen_random_uuid());p:=(j->>'id')::uuid;
 j:=public.pharmacy_command('supplier','{"name":"Verification","phone":"","contact":"","address":"","terms":30}',gen_random_uuid());s:=(j->>'id')::uuid;
 j:=public.pharmacy_command('purchase',jsonb_build_object('number','VERIFY','supplier_id',s,'date','2026-09-09','due','2026-12-09','attachment','','lines',jsonb_build_array(jsonb_build_object('product_id',p,'batch_no','V','production','2026-01-01','expiry','2099-01-01','cartons',1,'boxes',0,'strips',0,'units',0,'bonus',60,'carton_cost',300000,'discount',0))),rid);pi:=(j->>'id')::uuid;
 perform public.pharmacy_command('sale',jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('product_id',p,'unit','strip','quantity',1)),'discount',0,'method','نقدي'),gen_random_uuid());
 perform public.pharmacy_command('payment',jsonb_build_object('purchase_id',pi,'amount',100000,'date','2026-09-09','receipt','VERIFY','receipt_date','2026-09-09','method','نقدي'),gen_random_uuid());
 j:=public.pharmacy_snapshot();
 if (j->'batches'->0->>'quantity')::int<>650 or (j->'purchases'->0->>'total')::numeric<>300000 or (j->'sales'->0->>'total')::numeric<>2500 or (j->'payments'->0->>'amount')::numeric<>100000 then raise exception 'Verification failed';end if;
 execute 'reset role';
end $$;
rollback;
select 'Live purchase, sale, stock, payment and authenticated snapshot passed; verification records rolled back' as verification;
