export type Role='owner'|'sales'|'superadmin';
export type Product={id:string;name:string;scientific:string;barcode:string;category:string;form:string;strength:string;manufacturer:string;country:string;location:string;carton_boxes:number;box_strips:number;strip_units:number;base_unit:string;sell_unit:number;sell_strip:number;sell_box:number;sell_carton:number;min_stock:number;notes:string};
export type Supplier={id:string;name:string;contact:string;phone:string;address:string;terms:number};
export type Batch={id:string;product_id:string;supplier_id:string;purchase_id:string;batch_no:string;production:string;expiry:string;quantity:number;received:number;unit_cost?:number};
export type PurchaseLine={product_id:string;batch_no:string;production:string;expiry:string;cartons:number;boxes:number;strips:number;units:number;bonus:number;carton_cost:number;discount:number};
export type Purchase={id:string;number:string;supplier_id:string;date:string;due:string;total:number;attachment:string;lines:PurchaseLine[]};
export type Payment={id:string;supplier_id:string;purchase_id:string;amount:number;date:string;receipt:string;receipt_date:string;method:string;attachment:string;notes:string};
export type SaleLine={product_id:string;batch_id:string;name:string;unit:string;quantity:number;factor:number;price:number};
export type Sale={id:string;number:string;date:string;employee:string;customer:string;method:string;discount:number;total:number;lines:SaleLine[]};
export type Movement={id:string;product_id:string;batch_id:string;date:string;type:string;quantity:number;reference:string};
export type Tenant={id:string;name:string;owner:string;phone:string;address:string;active:boolean;expires:string};
export type Member={id:string;name:string;email:string;role:Role;tenant_id:string};
export type Data={products:Product[];suppliers:Supplier[];batches:Batch[];purchases:Purchase[];payments:Payment[];sales:Sale[];movements:Movement[];tenants:Tenant[];members:Member[]};
export type Command={action:string;payload:any;request_id:string};
export const emptyData=():Data=>({products:[],suppliers:[],batches:[],purchases:[],payments:[],sales:[],movements:[],tenants:[],members:[]});
export const uid=()=>crypto.randomUUID();
export const dayOf=(value:string|Date)=>new Date(value).toLocaleDateString('en-CA',{timeZone:'Asia/Baghdad'});
export const today=()=>dayOf(new Date());
export const number=(n:number)=>new Intl.NumberFormat('en-US',{maximumFractionDigits:2}).format(n||0);
export const money=(n:number)=>number(n)+' د.ع';
export const factors=(p:Product)=>({unit:1,strip:p.strip_units,box:p.strip_units*p.box_strips,carton:p.strip_units*p.box_strips*p.carton_boxes});
export const unitNames:Record<string,string>={unit:'مفرد',strip:'شريط / عبوة داخلية',box:'علبة',carton:'كارتون'};
export function pack(p:Product,n:number){const f=factors(p);const c=Math.floor(n/f.carton);n%=f.carton;const b=Math.floor(n/f.box);n%=f.box;const s=Math.floor(n/f.strip);n%=f.strip;return [c&&`${c} كارتون`,b&&`${b} علبة`,s&&`${s} شريط`,n&&`${n} ${p.base_unit}`].filter(Boolean).join('، ')||'نفد المخزون'}
export function stock(d:Data,id:string,available=false){return d.batches.filter(b=>b.product_id===id&&(!available||b.expiry>=today())).reduce((a,b)=>a+b.quantity,0)}
export function balance(d:Data,id:string){return d.purchases.filter(x=>x.supplier_id===id).reduce((a,x)=>a+x.total,0)-d.payments.filter(x=>x.supplier_id===id).reduce((a,x)=>a+x.amount,0)}
export function outstanding(d:Data,p:Purchase){return p.total-d.payments.filter(x=>x.purchase_id===p.id).reduce((a,x)=>a+x.amount,0)}
export function purchaseQuantity(p:Product,l:PurchaseLine){const f=factors(p);return l.cartons*f.carton+l.boxes*f.box+l.strips*f.strip+l.units+l.bonus}
function ensure(v:unknown,msg:string):asserts v{if(!v)throw Error(msg)}
function nonnegative(v:number){return Number.isFinite(v)&&v>=0}
export function applyCommand(input:Data,command:Command,role:Role,employee='صاحب الصيدلية'):Data{
 const d=structuredClone(input);const p=command.payload;const id=uid();const now=new Date().toISOString();
 ensure(role==='owner'||role==='superadmin'||command.action==='sale','ليست لديك صلاحية تنفيذ هذه العملية');
 switch(command.action){
 case 'product':{
 ensure(p.name?.trim(),'اسم المادة مطلوب');['carton_boxes','box_strips','strip_units'].forEach(k=>ensure(Number.isInteger(p[k])&&p[k]>0,'معاملات التعبئة يجب أن تكون أعداداً صحيحة موجبة'));
 ['sell_unit','sell_strip','sell_box','sell_carton','min_stock'].forEach(k=>ensure(nonnegative(p[k]),'الأسعار والحد الأدنى لا تقبل قيماً سالبة'));
 ensure(!p.barcode||!d.products.some(x=>x.barcode===p.barcode),'الباركود مسجل مسبقاً');d.products.push({...p,id});break;}
 case 'supplier':ensure(p.name?.trim(),'اسم الشركة مطلوب');d.suppliers.push({...p,id});break;
 case 'purchase':{
 ensure(d.suppliers.some(x=>x.id===p.supplier_id),'اختر الشركة المجهزة');ensure(p.number&&p.date&&p.due&&p.due>=p.date,'رقم الفاتورة وتواريخ صحيحة مطلوبة');ensure(!d.purchases.some(x=>x.number===p.number&&x.supplier_id===p.supplier_id),'رقم الفاتورة موجود لهذه الشركة');ensure(p.lines?.length,'أضف مادة واحدة على الأقل');let total=0;
 for(const l of p.lines as PurchaseLine[]){const product=d.products.find(x=>x.id===l.product_id);ensure(product,'المادة غير موجودة');ensure(l.batch_no&&l.production&&l.expiry>=today()&&l.expiry>l.production,'تحقق من التشغيلة وتاريخ الإنتاج والانتهاء');['cartons','boxes','strips','units','bonus'].forEach(k=>ensure(Number.isInteger((l as any)[k])&&(l as any)[k]>=0,'الكميات يجب أن تكون أعداداً صحيحة غير سالبة'));ensure(nonnegative(l.carton_cost)&&nonnegative(l.discount),'الكلفة والخصم غير صالحين');const q=purchaseQuantity(product,l);ensure(q>0,'الكمية يجب أن تكون أكبر من صفر');const cost=(q-l.bonus)*l.carton_cost/factors(product).carton-l.discount;ensure(cost>=0,'الخصم أكبر من كلفة المواد');total+=cost;const bid=uid();d.batches.push({id:bid,product_id:l.product_id,supplier_id:p.supplier_id,purchase_id:id,batch_no:l.batch_no,production:l.production,expiry:l.expiry,quantity:q,received:q,unit_cost:cost/q});d.movements.push({id:uid(),product_id:l.product_id,batch_id:bid,date:now,type:'شراء',quantity:q,reference:p.number});}
 d.purchases.push({...p,id,total:Math.round(total*100)/100});break;}
 case 'payment':{
 const purchase=d.purchases.find(x=>x.id===p.purchase_id);ensure(purchase,'اختر فاتورة المشتريات');ensure(nonnegative(p.amount)&&p.amount>0&&p.amount<=outstanding(d,purchase)+0.001,'المبلغ يجب أن يكون موجباً ولا يتجاوز المتبقي');ensure(p.receipt&&p.date&&p.receipt_date,'أدخل رقم وتاريخ الوصل وتاريخ الدفع');ensure(!d.payments.some(x=>x.supplier_id===purchase.supplier_id&&x.receipt===p.receipt),'رقم الوصل مسجل مسبقاً');d.payments.push({...p,id,supplier_id:purchase.supplier_id});break;}
 case 'sale':{
 ensure(p.lines?.length,'السلة فارغة');ensure(nonnegative(p.discount),'قيمة الخصم غير صالحة');ensure(role!=='sales'||p.discount===0,'الخصم متاح لصاحب الصيدلية فقط');let total=0;const lines:SaleLine[]=[];
 for(const l of p.lines){const product=d.products.find(x=>x.id===l.product_id);ensure(product,'المادة غير موجودة');const f=(factors(product) as any)[l.unit];const price=(product as any)['sell_'+l.unit];ensure(f&&Number.isInteger(l.quantity)&&l.quantity>0,'اختر وحدة وكمية صحيحة');let needed=l.quantity*f;ensure(stock(d,product.id,true)>=needed,'الكمية المطلوبة غير متوفرة: '+product.name);total+=price*l.quantity;
 for(const b of d.batches.filter(b=>b.product_id===product.id&&b.quantity>0&&b.expiry>=today()).sort((a,b)=>a.expiry.localeCompare(b.expiry)||a.id.localeCompare(b.id))){if(!needed)break;const take=Math.min(b.quantity,needed);b.quantity-=take;needed-=take;lines.push({product_id:product.id,batch_id:b.id,name:product.name,unit:l.unit,quantity:take/f,factor:f,price});d.movements.push({id:uid(),product_id:product.id,batch_id:b.id,date:now,type:'بيع',quantity:-take,reference:id});}}
 ensure(p.discount<=total,'الخصم يتجاوز الإجمالي');d.sales.push({id,number:'S-'+String(d.sales.length+1001),date:now,employee,customer:p.customer||'زبون نقدي',method:p.method||'نقدي',discount:p.discount,total:Math.round((total-p.discount)*100)/100,lines});break;}
 case 'adjust':{const b=d.batches.find(x=>x.id===p.batch_id);ensure(b,'اختر التشغيلة');ensure(Number.isInteger(p.quantity)&&p.quantity!==0&&b.quantity+p.quantity>=0,'كمية التعديل غير صالحة');ensure(p.reason?.trim(),'سبب التعديل مطلوب');b.quantity+=p.quantity;d.movements.push({id,product_id:b.product_id,batch_id:b.id,date:now,type:'تسوية: '+p.reason,quantity:p.quantity,reference:id});break;}
 case 'tenant':ensure(role==='superadmin','هذه العملية للسوبر أدمن');ensure(p.name&&p.owner,'اسم الصيدلية وصاحبها مطلوبان');d.tenants.push({...p,id,active:true});break;
 case 'tenant_status':ensure(role==='superadmin','هذه العملية للسوبر أدمن');d.tenants=d.tenants.map(x=>x.id===p.id?{...x,active:!x.active}:x);break;
 case 'member':ensure(p.email&&p.name&&['sales','owner'].includes(p.role),'أكمل بيانات الموظف');d.members.push({id,name:p.name,email:p.email,role:p.role,tenant_id:p.tenant_id});break;
 default:throw Error('عملية غير مدعومة');}
 return d;
}
