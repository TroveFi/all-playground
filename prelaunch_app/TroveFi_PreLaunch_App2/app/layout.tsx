import "./globals.css";
import type { Metadata } from "next";
import Web3Provider from "@/components/Web3Provider";
import { SITE } from "@/lib/site";

export const metadata: Metadata = {
  metadataBase: new URL(SITE.url),
  title: {
    default: "Coming Soon: TroveFi – No‑Loss Yield Lottery on Flow",
    template: `%s | ${SITE.name}`,
  },
  description:
    "Deposit with the crowd → everyone keeps principal → winners take the pooled yield. AI‑powered rebalancing on Flow blockchain.",
  keywords: SITE.keywords,
  alternates: { canonical: SITE.url },
  openGraph: {
    title: "Coming Soon: TroveFi – No‑Loss Yield Lottery on Flow",
    description:
      "Deposit with the crowd → everyone keeps principal → winners take the pooled yield.",
    url: SITE.url,
    siteName: SITE.name,
    type: "website",
    images: [SITE.ogImage],
  },
  twitter: {
    card: "summary_large_image",
    site: SITE.twitter,
    title: "Coming Soon: TroveFi – No‑Loss Yield Lottery on Flow",
    description:
      "Deposit with the crowd → everyone keeps principal → winners take the pooled yield.",
    images: [SITE.ogImage],
  },
  icons: {
    icon: "/favicon.png",
    apple: "/apple-touch-icon.png",
    shortcut: "/favicon.ico",
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        {/* Fallback explicit favicon link; /app/icon.png also auto-works */}
        <link rel="icon" href="/favicon.png" sizes="48x48" />
        {/* JSON‑LD: Site + Organization */}
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({
              "@context": "https://schema.org",
              "@type": "WebSite",
              name: SITE.name,
              url: SITE.url,
            }),
          }}
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({
              "@context": "https://schema.org",
              "@type": "Organization",
              name: SITE.name,
              url: SITE.url,
              logo: SITE.logo,
              sameAs: ["https://twitter.com/TroveFi"],
            }),
          }}
        />
      </head>
      <body className="font-sans antialiased bg-[var(--bg)] text-white overflow-x-hidden">
        <Web3Provider>{children}</Web3Provider>
      </body>
    </html>
  );
}