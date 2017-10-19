#!/bin/bash
AUDIT_FILE=/var/lib/mysql/data/server_audit.log
while [ ! -f "${AUDIT_FILE}" ]
do
  sleep 2
done
tail -n0 -f "${AUDIT_FILE}" | while IFS='' read -r line || [[ -n "$line" ]]; do
     echo $line > /proc/1/fd/1
done
