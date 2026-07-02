{ config, pkgs, ... }:

let
  podmanNetwork = "media_net";
  proxyScript = pkgs.writeText "proxy.py" ''
    from http.server import BaseHTTPRequestHandler, HTTPServer
    import json
    import urllib.request
    import urllib.error

    class ProxyHTTPRequestHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            content_length = int(self.headers["Content-Length"])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data)
            
            # Strip response_format if it is json_schema
            if "response_format" in data and data.get("response_format", {}).get("type") == "json_schema":
                print("Intercepted json_schema request. Converting to json_object.")
                # Add json instructions
                if "messages" in data and len(data["messages"]) > 0:
                    data["messages"][0]["content"] += "\nIMPORTANT: You must output a valid JSON object."
                data["response_format"] = {"type": "json_object"}
                
            req = urllib.request.Request(
                "https://api.deepseek.com/v1/chat/completions",
                data=json.dumps(data).encode("utf-8"),
                headers={
                    "Authorization": self.headers.get("Authorization"),
                    "Content-Type": "application/json"
                }
            )
            
            try:
                with urllib.request.urlopen(req) as response:
                    self.send_response(response.getcode())
                    for k, v in response.headers.items():
                        if k.lower() not in ["transfer-encoding"]:
                            self.send_header(k, v)
                    self.end_headers()
                    self.wfile.write(response.read())
            except urllib.error.HTTPError as e:
                self.send_response(e.code)
                for k, v in e.headers.items():
                    if k.lower() not in ["transfer-encoding"]:
                        self.send_header(k, v)
                self.end_headers()
                self.wfile.write(e.read())

    if __name__ == "__main__":
        server_address = ("", 4000)
        httpd = HTTPServer(server_address, ProxyHTTPRequestHandler)
        print("running custom deepseek proxy on port 4000")
        httpd.serve_forever()
  '';
in
{
  virtualisation.oci-containers.containers = {
    litellm = {
      image = "python:3.12-alpine";
      autoStart = true;
      extraOptions = [ "--network=${podmanNetwork}" ];
      
      ports = [
        "127.0.0.1:4000:4000"
      ];
      
      volumes = [
        "${proxyScript}:/proxy.py"
      ];
      
      cmd = [ "python" "-u" "/proxy.py" ];
    };
  };
}
