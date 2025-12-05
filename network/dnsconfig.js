// network/dnsconfig.js

// Define Providers
var REG_NONE = NewRegistrar("none");
var CF = NewDnsProvider("cloudflare");

var PROVIDERS = {
  "cloudflare": CF,
  "none": REG_NONE
};

// Load the Decrypted JSON
// We assume the shell script has already decrypted the data to this file.
// "require" in DNSControl works for .json files natively!
var config = require("dns_zones.json");

// Generate Domains
for (var domainName in config.domains) {
  var domainData = config.domains[domainName];
  var records = [];

  if (domainData.records) {
    for (var i = 0; i < domainData.records.length; i++) {
      var r = domainData.records[i];
      var modifiers = [];
      
      if (r.proxied === true) modifiers.push(CF_PROXY_ON);
      if (r.proxied === false) modifiers.push(CF_PROXY_OFF);

      records.push(DnsRecord(r.type, r.name, r.target, modifiers));
    }
  }

  D(domainName, 
    REG_NONE, 
    DnsProvider(PROVIDERS[domainData.provider]), 
    records
  );
}