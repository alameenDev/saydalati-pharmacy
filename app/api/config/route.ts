import {connectionStatus} from '@/lib/pharmacy/server';
export const dynamic='force-dynamic';
export async function GET(){return Response.json(await connectionStatus(),{headers:{'Cache-Control':'no-store'}})}
