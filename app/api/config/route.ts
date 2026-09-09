import {config} from '@/lib/pharmacy/server';
export async function GET(){const c=config();return Response.json({configured:!!(c.url&&c.key)},{headers:{'Cache-Control':'no-store'}})}
