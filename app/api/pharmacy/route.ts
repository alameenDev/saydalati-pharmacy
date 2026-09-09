import {failure,sameOrigin,session,snapshot,supabase} from '@/lib/pharmacy/server';
export async function GET(req:Request){try{return Response.json(await snapshot(req),{headers:{'Cache-Control':'no-store'}})}catch(e){return failure(e,401)}}
export async function POST(req:Request){try{sameOrigin(req);const {token,profile}=await session(req);const command:any=await req.json();if(command.action==='member'){
 await supabase('/functions/v1/pharmacy-accounts',{method:'POST',body:JSON.stringify(command)},token);
 }else await supabase('/rest/v1/rpc/pharmacy_command',{method:'POST',body:JSON.stringify({p_action:command.action,p_payload:command.payload,p_request_id:command.request_id})},token);
 return Response.json(await snapshot(req),{headers:{'Cache-Control':'no-store'}});
 }catch(e){return failure(e)}}
