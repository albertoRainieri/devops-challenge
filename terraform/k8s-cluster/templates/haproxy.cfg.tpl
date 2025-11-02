global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms

# Kubernetes API server proxy
listen k8s-api-6443
    bind *:6443
    mode tcp
    balance roundrobin
    server k8s_control_plane ${control_plane_ip}:6443 check

# HTTP frontend (for nginx ingress)
frontend http_frontend
    bind *:80
    mode http
    default_backend nginx_http_backend

# HTTPS frontend (for nginx ingress)
frontend https_frontend
    bind *:443
    mode tcp
    default_backend nginx_https_backend

# HTTP backend (nginx ingress NodePort)
backend nginx_http_backend
    mode http
    balance roundrobin
    option httpchk GET /healthz
    http-check expect status 200
%{ for idx, ip in worker_ips ~}
    server worker${idx + 1} ${ip}:30080 check
%{ endfor }

# HTTPS backend (nginx ingress NodePort)
backend nginx_https_backend
    mode tcp
    balance roundrobin
%{ for idx, ip in worker_ips ~}
    server worker${idx + 1} ${ip}:30443 check
%{ endfor }

