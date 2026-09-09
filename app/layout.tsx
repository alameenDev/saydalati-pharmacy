import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = { title: 'صيدلتي | إدارة الصيدليات', description: 'المبيعات والمخزون وحسابات الشركات في مكان واحد', icons: { icon: '/favicon.svg' } };
export default function RootLayout({children}:{children:React.ReactNode}){ return <html lang="ar" dir="rtl"><body>{children}</body></html> }
