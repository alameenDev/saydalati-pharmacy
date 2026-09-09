-- Saydalati v1. Apply once to the Supabase project selected by the owner.
-- All names are pharmacy-prefixed; this script does not modify unrelated objects.
begin;
create schema if not exists pharmacy_private;
revoke all on schema pharmacy_private from public, anon;
grant usage on schema pharmacy_private to authenticated;

create table public.pharmacy_tenants (
 id uuid primary key default gen_random_uuid(),name text not null check(length(trim(name))>0),owner text not null,
 phone text not null default '',address text not null default '',active boolean not null default true,expires date not null,
 created_at timestamptz not null default now()
);
create table public.pharmacy_members (
 id uuid primary key references auth.users(id) on delete cascade,name text not null,email text not null,
 role text not null check(role in ('superadmin','owner','sales')),tenant_id uuid references public.pharmacy_tenants(id),
 check((role='superadmin' and tenant_id is null) or (role<>'superadmin' and tenant_id is not null))
);
create index pharmacy_members_tenant on public.pharmacy_members(tenant_id);

create function pharmacy_private.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.pharmacy_members where id=auth.uid() and role='superadmin');
$$;
create function pharmacy_private.has_access(t uuid,owner_only boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.pharmacy_members m join public.pharmacy_tenants p on p.id=m.tenant_id
 where m.id=auth.uid() and m.tenant_id=t and (not owner_only or m.role='owner') and p.active and p.expires >= (now() at time zone 'Asia/Baghdad')::date);
$$;
revoke all on function pharmacy_private.is_admin() from public,anon;
revoke all on function pharmacy_private.has_access(uuid,boolean) from public,anon;
grant execute on function pharmacy_private.is_admin(),pharmacy_private.has_access(uuid,boolean) to authenticated;

create table public.pharmacy_products (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.pharmacy_tenants(id),
 data jsonb not null check(jsonb_typeof(data)='object'),unique(id,tenant_id)
);
create unique index pharmacy_product_barcode on public.pharmacy_products(tenant_id,(data->>'barcode')) where coalesce(data->>'barcode','')<>'';
create table public.pharmacy_suppliers (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.pharmacy_tenants(id),
 data jsonb not null,unique(id,tenant_id)
);
create table public.pharmacy_purchases (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.pharmacy_tenants(id),supplier_id uuid not null,
 number text not null,date date not null,due date not null,total numeric(18,2) not null check(total>=0),attachment text not null default '',
 lines jsonb not null,unique(id,tenant_id),unique(tenant_id,supplier_id,number),check(due>=date),
 foreign key(supplier_id,tenant_id) references public.pharmacy_suppliers(id,tenant_id)
);
create table public.pharmacy_batches (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.pharmacy_tenants(id),product_id uuid not null,supplier_id uuid not null,purchase_id uuid not null,
 batch_no text not null,production date not null,expiry date not null,quantity bigint not null check(quantity>=0),received bigint not null check(received>0),
 check(expiry>production),unique(id,tenant_id),
 foreign key(product_id,tenant_id) references public.pharmacy_products(id,tenant_id),
 foreign key(supplier_id,tenant_id) references public.pharmacy_suppliers(id,tenant_id),
 foreign key(purchase_id,tenant_id) references public.pharmacy_purchases(id,tenant_id)
);
create index pharmacy_batches_fefo on public.pharmacy_batches(tenant_id,product_id,expiry,id) where quantity>0;
create table public.pharmacy_batch_costs (
 batch_id uuid primary key,tenant_id uuid not null,unit_cost numeric(24,8) not null check(unit_cost>=0),
 foreign key(batch_id,tenant_id) references public.pharmacy_batches(id,tenant_id)
);
create table public.pharmacy_sales (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.pharmacy_tenants(id),
 number text not null,date timestamptz not null default now(),employee text not null,employee_id uuid not null references public.pharmacy_members(id),
 customer text not null,method text not null,discount numeric(18,2) not null check(discount>=0),total numeric(18,2) not null check(total>=0),lines jsonb not null,
 unique(tenant_id,number)
);
create table public.pharmacy_payments (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.pharmacy_tenants(id),supplier_id uuid not null,purchase_id uuid not null,
 amount numeric(18,2) not null check(amount>0),date date not null,receipt text not null,receipt_date date not null,
 method text not null,attachment text not null default '',notes text not null default '',unique(tenant_id,supplier_id,receipt),
 foreign key(purchase_id,tenant_id) references public.pharmacy_purchases(id,tenant_id),
 foreign key(supplier_id,tenant_id) references public.pharmacy_suppliers(id,tenant_id)
);
create table public.pharmacy_movements (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.pharmacy_tenants(id),product_id uuid not null,batch_id uuid not null,
 date timestamptz not null default now(),type text not null,quantity bigint not null,reference text not null,
 foreign key(product_id,tenant_id) references public.pharmacy_products(id,tenant_id),
 foreign key(batch_id,tenant_id) references public.pharmacy_batches(id,tenant_id)
);
create table pharmacy_private.requests (
 actor uuid not null,request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,created_at timestamptz not null default now(),
 primary key(actor,request_id)
);
alter table pharmacy_private.requests enable row level security;
revoke all on pharmacy_private.requests from public,anon,authenticated;

create index pharmacy_purchases_tenant_supplier on public.pharmacy_purchases(tenant_id,supplier_id);
create index pharmacy_purchases_supplier_fk on public.pharmacy_purchases(supplier_id,tenant_id);
create index pharmacy_batches_purchase_fk on public.pharmacy_batches(purchase_id,tenant_id);
create index pharmacy_batches_supplier_fk on public.pharmacy_batches(supplier_id,tenant_id);
create index pharmacy_batches_product_fk on public.pharmacy_batches(product_id,tenant_id);
create index pharmacy_sales_tenant_date on public.pharmacy_sales(tenant_id,date);
create index pharmacy_sales_employee_fk on public.pharmacy_sales(employee_id);
create index pharmacy_payments_invoice_fk on public.pharmacy_payments(purchase_id,tenant_id);
create index pharmacy_payments_supplier_fk on public.pharmacy_payments(supplier_id,tenant_id);
create index pharmacy_payments_tenant on public.pharmacy_payments(tenant_id);
create index pharmacy_movements_product_fk on public.pharmacy_movements(product_id,tenant_id);
create index pharmacy_movements_batch_fk on public.pharmacy_movements(batch_id,tenant_id);
create index pharmacy_movements_tenant_date on public.pharmacy_movements(tenant_id,date);
create index pharmacy_costs_tenant on public.pharmacy_batch_costs(tenant_id);
-- No direct writes from the browser. Commands validate and commit complete operations atomically.
alter table public.pharmacy_tenants enable row level security;
alter table public.pharmacy_members enable row level security;
create policy pharmacy_tenants_read on public.pharmacy_tenants for select to authenticated using(pharmacy_private.is_admin() or pharmacy_private.has_access(id));
create policy pharmacy_members_read on public.pharmacy_members for select to authenticated using(id=(select auth.uid()) or pharmacy_private.is_admin() or pharmacy_private.has_access(tenant_id,true));
do $$ declare t text; begin
 foreach t in array array['pharmacy_products','pharmacy_suppliers','pharmacy_batches','pharmacy_purchases','pharmacy_payments','pharmacy_batch_costs','pharmacy_movements','pharmacy_sales'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('create policy %I on public.%I for select to authenticated using (pharmacy_private.has_access(tenant_id,%L))',t||'_read',t,t in ('pharmacy_suppliers','pharmacy_purchases','pharmacy_payments','pharmacy_batch_costs','pharmacy_movements'));
 end loop;
 foreach t in array array['pharmacy_tenants','pharmacy_members','pharmacy_products','pharmacy_suppliers','pharmacy_batches','pharmacy_purchases','pharmacy_payments','pharmacy_batch_costs','pharmacy_movements','pharmacy_sales'] loop
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;

create function public.pharmacy_snapshot() returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare m public.pharmacy_members; result jsonb; begin
 select * into m from public.pharmacy_members where id=auth.uid();
 if m.id is null then raise exception 'الحساب غير مربوط بصيدلية'; end if;
 if m.role='superadmin' then
 return jsonb_build_object('products','[]'::jsonb,'suppliers','[]'::jsonb,'batches','[]'::jsonb,'purchases','[]'::jsonb,'payments','[]'::jsonb,'sales','[]'::jsonb,'movements','[]'::jsonb,
 'tenants',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from public.pharmacy_tenants t),
 'members',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from public.pharmacy_members t));
 end if;
 if not pharmacy_private.has_access(m.tenant_id) then raise exception 'الصيدلية موقوفة أو انتهى اشتراكها'; end if;
 result:=jsonb_build_object(
 'products',(select coalesce(jsonb_agg(data||jsonb_build_object('id',id)),'[]'::jsonb) from public.pharmacy_products where tenant_id=m.tenant_id),
 'suppliers',(select coalesce(jsonb_agg(data||jsonb_build_object('id',id)),'[]'::jsonb) from public.pharmacy_suppliers where tenant_id=m.tenant_id),
 'batches',(select coalesce(jsonb_agg((to_jsonb(b)-'tenant_id')||case when m.role='owner' then jsonb_build_object('unit_cost',c.unit_cost) else '{}'::jsonb end),'[]'::jsonb) from public.pharmacy_batches b left join public.pharmacy_batch_costs c on c.batch_id=b.id where b.tenant_id=m.tenant_id),
 'purchases',(select coalesce(jsonb_agg(to_jsonb(t)-'tenant_id'),'[]'::jsonb) from public.pharmacy_purchases t where tenant_id=m.tenant_id),
 'payments',(select coalesce(jsonb_agg(to_jsonb(t)-'tenant_id'),'[]'::jsonb) from public.pharmacy_payments t where tenant_id=m.tenant_id),
 'sales',(select coalesce(jsonb_agg(to_jsonb(t)-'tenant_id' order by date),'[]'::jsonb) from public.pharmacy_sales t where tenant_id=m.tenant_id and (m.role='owner' or employee_id=m.id)),
 'movements',(select coalesce(jsonb_agg(to_jsonb(t)-'tenant_id' order by date),'[]'::jsonb) from public.pharmacy_movements t where tenant_id=m.tenant_id),
 'tenants',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from public.pharmacy_tenants t where id=m.tenant_id),
 'members',(select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) from public.pharmacy_members t where tenant_id=m.tenant_id));
 return result;
end $$;
revoke all on function public.pharmacy_snapshot() from public,anon;
grant execute on function public.pharmacy_snapshot() to authenticated;

-- Private, privileged transaction implementation; every branch verifies the current database membership.
create function pharmacy_private.command(p_action text,p_payload jsonb,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
<<tx>>
declare
 m public.pharmacy_members; p jsonb:=p_payload; row_product public.pharmacy_products; b public.pharmacy_batches;
 pur public.pharmacy_purchases; tenant uuid; rid uuid:=gen_random_uuid(); bid uuid; line jsonb; doc jsonb;
 existing pharmacy_private.requests; qty bigint; bonus bigint; pack_factor bigint; base_factor bigint;
 total numeric:=0; line_total numeric; price numeric; take_qty bigint; needed bigint; disc numeric; amount numeric;
 expiry_date date; prod_date date; current_day date:=(now() at time zone 'Asia/Baghdad')::date;
 sale_lines jsonb:='[]'::jsonb; result jsonb; key text; num text; unit text;
begin
 if auth.uid() is null then raise exception 'يرجى تسجيل الدخول'; end if;
 select * into m from public.pharmacy_members where id=auth.uid();
 if m.id is null then raise exception 'حساب غير معتمد'; end if;
 if p_request_id is null or jsonb_typeof(p)<>'object' then raise exception 'طلب غير صالح'; end if;
 tenant:=m.tenant_id;
 -- A tenant row lock serializes stock, supplier debt and invoice number updates.
 if m.role<>'superadmin' then
 perform 1 from public.pharmacy_tenants where id=tenant for update;
 if not pharmacy_private.has_access(tenant) then raise exception 'الصيدلية موقوفة أو انتهى اشتراكها'; end if;
 else
 perform pg_advisory_xact_lock(hashtextextended(m.id::text,0));
 if p_action not in ('tenant','tenant_status','member') then raise exception 'هذه العملية غير متاحة للسوبر أدمن'; end if;
 end if;
 if m.role='sales' and p_action<>'sale' then raise exception 'ليست لديك صلاحية تنفيذ العملية'; end if;
 select * into existing from pharmacy_private.requests where actor=m.id and request_id=p_request_id;
 if found then
 if existing.action<>p_action or existing.payload<>p then raise exception 'معرف الطلب مستخدم لعملية أخرى'; end if;
 return existing.result;
 end if;
 case p_action
 when 'product' then
 if coalesce(trim(p->>'name'),'')='' then raise exception 'اسم المادة مطلوب'; end if;
 foreach key in array array['carton_boxes','box_strips','strip_units'] loop
 if coalesce((p->>key)::bigint,0)<=0 or (p->>key)::bigint>100000 then raise exception 'معاملات التعبئة غير صالحة'; end if;
 end loop;
 foreach key in array array['sell_unit','sell_strip','sell_box','sell_carton','min_stock'] loop
 if p->>key is null or (p->>key)::numeric<0 or (p->>key)::numeric>1000000000000 then raise exception 'الأسعار والحد الأدنى غير صالحين'; end if;
 end loop;
 insert into public.pharmacy_products(id,tenant_id,data) values(rid,tenant,p-'id'-'tenant_id');
 when 'supplier' then
 if coalesce(trim(p->>'name'),'')='' or coalesce((p->>'terms')::int,0)<0 then raise exception 'بيانات الشركة غير مكتملة'; end if;
 insert into public.pharmacy_suppliers(id,tenant_id,data) values(rid,tenant,p-'id'-'tenant_id');
 when 'purchase' then
 if coalesce(trim(p->>'number'),'')='' or p->>'date' is null or p->>'due' is null or (p->>'due')::date<(p->>'date')::date then raise exception 'رقم الفاتورة والتواريخ مطلوبة'; end if;
 if not exists(select 1 from public.pharmacy_suppliers where id=(p->>'supplier_id')::uuid and tenant_id=tenant) then raise exception 'الشركة غير موجودة'; end if;
 if jsonb_typeof(p->'lines') is distinct from 'array' or jsonb_array_length(p->'lines')=0 then raise exception 'أضف مواد الفاتورة'; end if;
 if coalesce(p->>'attachment','')<>'' and (p->>'attachment') not like tenant::text||'/%' then raise exception 'مسار المرفق غير صالح'; end if;
 insert into public.pharmacy_purchases(id,tenant_id,supplier_id,number,date,due,total,attachment,lines)
 values(rid,tenant,(p->>'supplier_id')::uuid,p->>'number',(p->>'date')::date,(p->>'due')::date,0,coalesce(p->>'attachment',''),p->'lines');
 for line in select value from jsonb_array_elements(p->'lines') loop
 select * into row_product from public.pharmacy_products where id=(line->>'product_id')::uuid and tenant_id=tenant;
 if not found then raise exception 'المادة غير موجودة في الصيدلية'; end if;
 if coalesce(trim(line->>'batch_no'),'')='' or line->>'production' is null or line->>'expiry' is null then raise exception 'التشغيلة وتواريخها مطلوبة'; end if;
 prod_date:=(line->>'production')::date;expiry_date:=(line->>'expiry')::date;
 if expiry_date<=prod_date or expiry_date<current_day then raise exception 'تواريخ الصلاحية غير مقبولة'; end if;
 foreach key in array array['cartons','boxes','strips','units','bonus'] loop
 if line->>key is null or (line->>key)::bigint<0 then raise exception 'الكميات يجب أن تكون أعداداً صحيحة غير سالبة'; end if;
 end loop;
 if line->>'carton_cost' is null or (line->>'carton_cost')::numeric<0 or line->>'discount' is null or (line->>'discount')::numeric<0 then raise exception 'كلفة أو خصم غير صالح'; end if;
 doc:=row_product.data;
 pack_factor:=(doc->>'carton_boxes')::bigint*(doc->>'box_strips')::bigint*(doc->>'strip_units')::bigint;
 bonus:=(line->>'bonus')::bigint;
 qty:=(line->>'cartons')::bigint*pack_factor+(line->>'boxes')::bigint*(doc->>'box_strips')::bigint*(doc->>'strip_units')::bigint+(line->>'strips')::bigint*(doc->>'strip_units')::bigint+(line->>'units')::bigint+bonus;
 if qty<=0 then raise exception 'الكمية يجب أن تكون أكبر من صفر'; end if;
 line_total:=(qty-bonus)*(line->>'carton_cost')::numeric/pack_factor-(line->>'discount')::numeric;
 if line_total<0 then raise exception 'الخصم يتجاوز قيمة المادة'; end if;
 bid:=gen_random_uuid();
 insert into public.pharmacy_batches(id,tenant_id,product_id,supplier_id,purchase_id,batch_no,production,expiry,quantity,received)
 values(bid,tenant,row_product.id,(p->>'supplier_id')::uuid,rid,line->>'batch_no',prod_date,expiry_date,qty,qty);
 insert into public.pharmacy_batch_costs(batch_id,tenant_id,unit_cost) values(bid,tenant,line_total/qty);
 insert into public.pharmacy_movements(tenant_id,product_id,batch_id,type,quantity,reference) values(tenant,row_product.id,bid,'شراء',qty,p->>'number');
 total:=total+line_total;
 end loop;
 update public.pharmacy_purchases set total=round(tx.total,2) where id=rid;
 when 'payment' then
 select * into pur from public.pharmacy_purchases where id=(p->>'purchase_id')::uuid and tenant_id=tenant for update;
 if not found then raise exception 'الفاتورة غير موجودة'; end if;
 amount:=(p->>'amount')::numeric;
 if amount is null or amount<=0 or amount>pur.total-(select coalesce(sum(x.amount),0) from public.pharmacy_payments x where x.purchase_id=pur.id) then raise exception 'المبلغ يتجاوز المتبقي أو غير صالح'; end if;
 if coalesce(trim(p->>'receipt'),'')='' or p->>'date' is null or p->>'receipt_date' is null or coalesce(p->>'method','') not in ('نقدي','تحويل','صك','بطاقة') then raise exception 'أكمل بيانات الوصل'; end if;
 if coalesce(p->>'attachment','')<>'' and (p->>'attachment') not like tenant::text||'/%' then raise exception 'مسار المرفق غير صالح'; end if;
 insert into public.pharmacy_payments(id,tenant_id,supplier_id,purchase_id,amount,date,receipt,receipt_date,method,attachment,notes)
 values(rid,tenant,pur.supplier_id,pur.id,amount,(p->>'date')::date,p->>'receipt',(p->>'receipt_date')::date,p->>'method',coalesce(p->>'attachment',''),coalesce(p->>'notes',''));
 when 'sale' then
 disc:=(p->>'discount')::numeric;
 if disc is null or disc<0 or m.role='sales' and disc<>0 then raise exception 'خصم غير مسموح'; end if;
 if jsonb_typeof(p->'lines') is distinct from 'array' or jsonb_array_length(p->'lines')=0 then raise exception 'السلة فارغة'; end if;
 if coalesce(p->>'method','') not in ('نقدي','بطاقة','تحويل') then raise exception 'طريقة الدفع غير صالحة'; end if;
 for line in select value from jsonb_array_elements(p->'lines') loop
 select * into row_product from public.pharmacy_products where id=(line->>'product_id')::uuid and tenant_id=tenant;
 if not found then raise exception 'المادة غير موجودة'; end if;
 doc:=row_product.data;unit:=line->>'unit';qty:=(line->>'quantity')::bigint;
 if qty is null or qty<=0 or unit is null or unit not in ('unit','strip','box','carton') then raise exception 'كمية أو وحدة غير صالحة'; end if;
 base_factor:=case unit when 'unit' then 1 when 'strip' then (doc->>'strip_units')::bigint when 'box' then (doc->>'strip_units')::bigint*(doc->>'box_strips')::bigint when 'carton' then (doc->>'strip_units')::bigint*(doc->>'box_strips')::bigint*(doc->>'carton_boxes')::bigint end;
 price:=(doc->>('sell_'||unit))::numeric;needed:=qty*base_factor;total:=total+price*qty;
 for b in select * from public.pharmacy_batches where tenant_id=tenant and product_id=row_product.id and quantity>0 and expiry>=current_day order by expiry,id for update loop
 exit when needed=0;
 take_qty:=least(needed,b.quantity);needed:=needed-take_qty;
 update public.pharmacy_batches set quantity=quantity-take_qty where id=b.id;
 sale_lines:=sale_lines||jsonb_build_array(jsonb_build_object('product_id',row_product.id,'batch_id',b.id,'name',doc->>'name','unit',unit,'quantity',take_qty::numeric/base_factor,'factor',base_factor,'price',price));
 insert into public.pharmacy_movements(tenant_id,product_id,batch_id,type,quantity,reference) values(tenant,row_product.id,b.id,'بيع',-take_qty,rid::text);
 end loop;
 if needed>0 then raise exception 'الكمية المتاحة لا تكفي للمادة %',doc->>'name'; end if;
 end loop;
 if disc>total then raise exception 'الخصم يتجاوز الإجمالي'; end if;
 select 'S-'||(1001+count(*))::text into num from public.pharmacy_sales where tenant_id=tenant;
 insert into public.pharmacy_sales(id,tenant_id,number,employee,employee_id,customer,method,discount,total,lines)
 values(rid,tenant,num,m.name,m.id,coalesce(nullif(p->>'customer',''),'زبون نقدي'),p->>'method',disc,round(total-disc,2),sale_lines);
 when 'adjust' then
 select * into b from public.pharmacy_batches where id=(p->>'batch_id')::uuid and tenant_id=tenant for update;
 if not found then raise exception 'التشغيلة غير موجودة'; end if;
 qty:=(p->>'quantity')::bigint;
 if qty is null or qty=0 or b.quantity+qty<0 or coalesce(trim(p->>'reason'),'')='' then raise exception 'كمية أو سبب التعديل غير صالح'; end if;
 update public.pharmacy_batches set quantity=quantity+qty where id=b.id;
 insert into public.pharmacy_movements(tenant_id,product_id,batch_id,type,quantity,reference) values(tenant,b.product_id,b.id,'تسوية: '||(p->>'reason'),qty,rid::text);
 when 'tenant' then
 if m.role<>'superadmin' then raise exception 'صلاحية السوبر أدمن مطلوبة'; end if;
 insert into public.pharmacy_tenants(id,name,owner,phone,address,expires) values(rid,p->>'name',p->>'owner',coalesce(p->>'phone',''),coalesce(p->>'address',''),(p->>'expires')::date);
 when 'tenant_status' then
 if m.role<>'superadmin' then raise exception 'صلاحية السوبر أدمن مطلوبة'; end if;
 update public.pharmacy_tenants set active=not active where id=(p->>'id')::uuid;
 if not found then raise exception 'الصيدلية غير موجودة'; end if;
 when 'member' then
 if coalesce(p->>'role','') not in ('owner','sales') or coalesce(p->>'tenant_id','')='' then raise exception 'صلاحية الحساب أو الصيدلية غير صالحة'; end if;
 if m.role<>'superadmin' and (m.role<>'owner' or p->>'role'<>'sales' or (p->>'tenant_id')::uuid<>tenant) then raise exception 'غير مخول لإنشاء هذا الحساب'; end if;
 if not exists(select 1 from auth.users u where u.id=(p->>'id')::uuid and lower(u.email)=lower(p->>'email')) then raise exception 'حساب الدخول غير موجود'; end if;
 insert into public.pharmacy_members(id,name,email,role,tenant_id) values((p->>'id')::uuid,p->>'name',p->>'email',p->>'role',(p->>'tenant_id')::uuid);
 else raise exception 'عملية غير مدعومة';
 end case;
 result:=jsonb_build_object('id',rid,'ok',true);
 insert into pharmacy_private.requests(actor,request_id,action,payload,result) values(m.id,p_request_id,p_action,p,result);
 return result;
end $$;
revoke all on function pharmacy_private.command(text,jsonb,uuid) from public,anon;
grant execute on function pharmacy_private.command(text,jsonb,uuid) to authenticated;
create function public.pharmacy_command(p_action text,p_payload jsonb,p_request_id uuid) returns jsonb language sql security invoker set search_path='' as $$
 select pharmacy_private.command(p_action,p_payload,p_request_id);
$$;
revoke all on function public.pharmacy_command(text,jsonb,uuid) from public,anon;
grant execute on function public.pharmacy_command(text,jsonb,uuid) to authenticated;

-- Purchase invoices and payment receipts are private files.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('pharmacy-documents','pharmacy-documents',false,5242880,array['image/jpeg','image/png','application/pdf']);
create policy pharmacy_documents_read on storage.objects for select to authenticated using(bucket_id='pharmacy-documents' and pharmacy_private.has_access(((storage.foldername(name))[1])::uuid,true));
create policy pharmacy_documents_insert on storage.objects for insert to authenticated with check(bucket_id='pharmacy-documents' and pharmacy_private.has_access(((storage.foldername(name))[1])::uuid,true));
commit;
