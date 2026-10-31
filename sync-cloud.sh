#!/bin/bash
LOCAL_JSON="$HOME/Library/Application Support/AntigravityQuotaBar/quota.json"
if [ -f "$LOCAL_JSON" ]; then
    curl -s --max-time 15 -T "$LOCAL_JSON" -u "kgbdufo123:Y8vxGJOvjP" "ftp://147.50.231.17/httpdocs/quota/quota.json" >/dev/null 2>&1
fi
