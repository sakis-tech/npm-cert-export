#!/bin/bash

zone=example.com              # Please enter your domain here
dnsrecord=mail.example.com    # Please enter your mailcow domain here

## Cloudflare authentication details
## keep these private
cloudflare_token="xxxxxxx"    # Please enter your created cloudflare token here

# get certificate hash
chain_hash=$(openssl x509 -in /opt/mailcow-dockerized/data/assets/ssl/cert.pem -noout -pubkey | openssl pkey -pubin -outform DER | openssl dgst -sha512 -binary | hexdump -ve '/1 "%02x"')

# get the zone id for the requested zone
zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone&status=active" \
  -H "Authorization: Bearer $cloudflare_token" \
  -H "Content-Type: application/json" | jq -r '{"result"}[] | .[0] | .id')

echo "ID for $zone is $zone_id"

ports=("_25._tcp")

for i in "${ports[@]}"
do
    # get the dns record id
    dnsrecord_req=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=TLSA&name=$i.$dnsrecord" \
        -H "Authorization: Bearer $cloudflare_token" \
        -H "Content-Type: application/json")
    
    dnsrecord_id=$(echo "$dnsrecord_req" | jq -r '{"result"}[] | .[0] | .id')
    dnsrecord_hash=$(echo "$dnsrecord_req" | jq -r '{"result"}[] | .[0] | .data.certificate')

    echo "Processing record $i.$dnsrecord ..."

    if [ -z "$dnsrecord_id" ] || [ $dnsrecord_id == "null" ]
    then
        # Add the record
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
            -H "Authorization: Bearer $cloudflare_token" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"TLSA\",\"name\":\"$i.$dnsrecord\", \"data\": {\"usage\": \"3\", \"selector\": \"1\", \"matching_type\": \"1\", \"certificate\":\"$chain_hash\"},\"ttl\":1,\"proxied\":false}" | jq
        
        echo "Record $i.$dnsrecord added!"
    else
        if [[ "$dnsrecord_hash" != "$chain_hash" ]]
        then
            # Update the record
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
