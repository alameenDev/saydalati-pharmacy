declare const Deno:any;
Deno.serve(async(req:Request)=>{
 const url=Deno.env.get('SUPABASE_URL'),key=Deno.env.get('SUPABASE_ANON_KEY'),secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
 const authorization=req.headers.get('Authorization')||'';
 async function api(path:string,body?:unknown,admin=false,method?:string){
  const r=await fetch(url+path,{method:method||(body?'POST':'GET'),headers:{apikey:admin?secret:key,Authorization:admin?'Bearer '+secret:authorization,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
  const x:any=await r.json().catch(()=>null);if(!r.ok)throw Error(x?.message||x?.msg||'تعذر تنفيذ العملية');return x;
 }
 try{
  if(req.method!=='POST')return Response.json({error:'Method not allowed'},{status:405});
  const user=await api('/auth/v1/user');
  const rows=await api('/rest/v1/pharmacy_members?id=eq.'+user.id+'&select=*');const profile=rows[0];
  const {payload:p,request_id}=await req.json() as any;
  if(!profile||!p||!(profile.role==='superadmin'||profile.role==='owner'&&p.role==='sales'&&p.tenant_id===profile.tenant_id)||!['owner','sales'].includes(p.role))throw Error('غير مخول لإنشاء الحساب');
  if(typeof p.email!=='string'||typeof p.name!=='string'||typeof p.password!=='string'||p.password.length<12)throw Error('أكمل بيانات الحساب وكلمة مرور من 12 حرفاً');
  const tenants=await api('/rest/v1/pharmacy_tenants?id=eq.'+encodeURIComponent(p.tenant_id)+'&select=id');if(!tenants.length)throw Error('الصيدلية غير متاحة');
  const created=await api('/auth/v1/admin/users',{email:p.email,password:p.password,email_confirm:true},true);
  try{await api('/rest/v1/rpc/pharmacy_command',{p_action:'member',p_payload:{id:created.id,name:p.name,email:p.email,role:p.role,tenant_id:p.tenant_id},p_request_id:request_id})}
  catch(e){await api('/auth/v1/admin/users/'+created.id,undefined,true,'DELETE');throw e}
  return Response.json({ok:true});
 }catch(e){return Response.json({error:e instanceof Error?e.message:'تعذر إنشاء الحساب'},{status:400})}
});
