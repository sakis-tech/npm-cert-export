#!/bin/bash

zone=example.com              # Please enter your domain here
dnsrecord=mail.example.com    # Please enter your mailcow domain here

## Cloudflare authentication details
## keep these private
cloudflare_token="xxxxxxxxxxxxxxxxxxx"    # Please enter your created cloudflare token here

# Berechne den SHA-256 Hash des öffentlichen Schlüssels (SubjectPublicKeyInfo)
chain_hash=$(openssl x509 -in /opt/mailcow-dockerized/data/assets/ssl/cert.pem -pubkey -noout | \
  openssl pkey -pubin -outform DER | \
  openssl dgst -sha256 -binary | \
  xxd -p -c 256)

# Der Hash muss genau 64 Zeichen lang sein (256 Bit = 64 Hexadezimalzeichen)
echo "Calculated public key hash: $chain_hash"

# Hole die Zone-ID von Cloudflare
zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone&status=active" \
  -H "Authorization: Bearer $cloudflare_token" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

echo "Zone ID for $zone is $zone_id"

ports=("_25._tcp")

for i in "${ports[@]}"
do
    # Hole die bestehende TLSA DNS-Record-ID
    dnsrecord_req=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=TLSA&name=$i.$dnsrecord" \
        -H "Authorization: Bearer $cloudflare_token" \
        -H "Content-Type: application/json")
    
    dnsrecord_id=$(echo "$dnsrecord_req" | jq -r '.result[0].id')
    dnsrecord_hash=$(echo "$dnsrecord_req" | jq -r '.result[0].data.certificate')

    echo "Processing record $i.$dnsrecord ..."

    if [ -z "$dnsrecord_id" ] || [ "$dnsrecord_id" == "null" ]; then
        # Wenn der TLSA-Record nicht existiert, füge ihn hinzu
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
            -H "Authorization: Bearer $cloudflare_token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"TLSA\",\"name\":\"$i.$dnsrecord\", \"data\": {\"usage\": \"3\", \"selector\": \"1\", \"matching_type\": \"1\", \"certificate\":\"$chain_hash\"},\"ttl\":1,\"proxied\":false}" | jq
        
        echo "Record $i.$dnsrecord added!"
    else
        # Wenn der Record existiert, überprüfe, ob er aktualisiert werden muss
        if [[ "$dnsrecord_hash" != "$chain_hash" ]]; then
            # Wenn der Hash unterschiedlich ist, aktualisiere den Record
            curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$dnsrecord_id" \
                -H "Authorization: Bearer $cloudflare_token" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"TLSA\",\"name\":\"$i.$dnsrecord\", \"data\": {\"usage\": \"3\", \"selector\": \"1\", \"matching_type\": \"1\", \"certificate\":\"$chain_hash\"},\"ttl\":1,\"proxied\":false}" | jq

            echo "Record $i.$dnsrecord updated!"
        else
            echo "Record $i.$dnsrecord does not need to be updated!"
        fi
    fi
done
