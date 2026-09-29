docker run --net ptero_network -e TZ=Asia/Seoul -p 9203:9200 -p 5601:5601 \
-v /var/lib/elk/elasticsearch:/var/lib/elasticsearch \
-v /var/lib/elk/logstash:/var/lib/logstash \
-v /var/lib/elk/kibana:/var/lib/kibana \
-v /etc/ssl/certs/nginx-selfsigned.crt:/usr/share/kibana/config/certificate.crt \
-v /etc/ssl/private/nginx-selfsigned.key:/usr/share/kibana/config/private.key \
--restart unless-stopped \
-it -d --name dashboard apptestai/dashboard:1.1
