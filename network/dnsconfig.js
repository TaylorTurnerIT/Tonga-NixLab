// network/dnsconfig.js

// --- Providers ---
var REG_NONE = NewRegistrar("none"); // We don't manage registration via API
var CF = NewDnsProvider("cloudflare"); // Managed via Cloudflare

// --- Variables ---
var VPS_IP = "129.153.13.212"; // Oracle VPS IP

// --- Domains ---
D("tongatime.us", REG_NONE, DnsProvider(CF),
    // Root Record (The VPS Proxy)
    A("@", VPS_IP, CF_PROXY_OFF),

    // Minecraft Subdomain
    // Minecraft requires raw TCP/UDP, so we disable Cloudflare Proxy (Orange Cloud) else users cannot connect.
    A("mc", VPS_IP, CF_PROXY_OFF),

    // Proxmox / Homelab (Internal Only)
    A("proxmox", "100.73.119.72", CF_PROXY_OFF),

    // SPF Record
    TXT("@", "v=spf1 -all")
);