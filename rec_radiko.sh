#!/bin/bash

pid=$$
date=`date '+%Y-%m-%d-%H_%M'`
playerurl=http://radiko.jp/apps/js/flash/myplayer-release.swf
playerfile="/tmp/pre_player.swf"
keyfile="/tmp/pre_authkey.png"
cookiefile="/tmp/pre_cookie_${pid}_${date}.txt"


if [ $# -le 1 ]; then
    echo "usage : $0 channel_name duration(seconds)"
    exit 1
fi

channel=$1
DURATION=$2
filename=$3
outdir=$4

function get_player {
    echo "get player"
    if [ ! -f $playerfile ]; then
        wget -q -O $playerfile $playerurl

        if [ $? -ne 0 ]; then
            echo "failed get player"
            exit 1
        fi
    fi
}

function get_keydata {
    echo "get keydata"
    if [ ! -f $keyfile ]; then
        swfextract -b 12 $playerfile -o $keyfile

        if [ ! -f $keyfile ]; then
            echo "failed get keydata"
            exit 1
        fi
    fi
}

function access_auth1_fms {
    echo "access_auth1_fms"
    if [ -f auth1_fms_${pid} ]; then
        rm -f auth1_fms_${pid}
    fi

    wget -q \
        --header="pragma: no-cache" \
        --header="X-Radiko-App: pc_ts" \
        --header="X-Radiko-App-Version: 4.0.1" \
        --header="X-Radiko-User: test-stream" \
        --header="X-Radiko-Device: pc" \
        --post-data='\r\n' \
        --no-check-certificate \
        --load-cookies $cookiefile \
        --save-headers \
        -O /tmp/auth1_fms_${pid} \
        https://radiko.jp/v2/api/auth1_fms

    if [ $? -ne 0 ]; then
        echo "failed auth1 process"
        exit 1
    fi
}

function get_partial_key {
    echo "get_partial_key"
    authtoken=`awk '/X-Radiko-AuthToken:/ { print $2 }' /tmp/auth1_fms_${pid} | tr -d '\r\n'`
    if [ -z $authtoken ]; then
        authtoken=`awk '/X-RADIKO-AUTHTOKEN:/ { print $2 }' /tmp/auth1_fms_${pid} | tr -d '\r\n'`
    fi
    offset=`awk '/X-Radiko-KeyOffset:/ { print $2 }' /tmp/auth1_fms_${pid} | tr -d '\r\n'`
    length=`awk '/X-Radiko-KeyLength:/ { print $2 }' /tmp/auth1_fms_${pid} | tr -d '\r\n'`

    partialkey=`dd if=$keyfile bs=1 skip=${offset} count=${length} 2> /dev/null | base64`

    echo "authtoken: ${authtoken}"
    echo "offset: ${offset}"
    echo "length: ${length}"
    echo "partialkey: $partialkey"

    rm -f /tmp/auth1_fms_${pid}
}

function access_auth2_fms {
    echo "access_auth2_fms"
    if [ -f /tmp/auth2_fms_${pid} ]; then
        rm -f /tmp/auth2_fms_${pid}
    fi

    wget -q \
        --header="pragma: no-cache" \
        --header="X-Radiko-App: pc_ts" \
        --header="X-Radiko-App-Version: 4.0.0" \
        --header="X-Radiko-User: test-stream" \
        --header="X-Radiko-Device: pc" \
        --header="X-Radiko-Authtoken: ${authtoken}" \
        --header="X-Radiko-Partialkey: ${partialkey}" \
        --post-data='\r\n' \
        --load-cookies $cookiefile \
        --no-check-certificate \
        -O /tmp/auth2_fms_${pid} \
        https://radiko.jp/v2/api/auth2_fms

    if [ $? -ne 0 -o ! -f /tmp/auth2_fms_${pid} ]; then
        echo "failed auth2 process"
        return 1
    else
        echo "authentication success"
        rm -f /tmp/auth2_fms_${pid}
        return 0
    fi
}

function auth {
    get_player
    get_keydata
    access_auth1_fms
    get_partial_key
    access_auth2_fms
    if [ $? -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

function get_stream_url {
    echo "get_stream_url"
    if [ -f /tmp/${channel}.xml ]; then
        rm -f /tmp/${channel}.xml
    fi

    wget -q "http://radiko.jp/v2/station/stream/${channel}.xml" -O /tmp/${channel}.xml

    stream_url=`echo "cat /url/item[1]/text()" | xmllint --shell /tmp/${channel}.xml | tail -2 | head -1`
    rtmpdump_r=${stream_url%/*/*/*.*}
    rtmpdump_app=${stream_url%/*.*}
    rtmpdump_app=${rtmpdump_app##*jp/}
    rtmpdump_playpath=${stream_url##*/}
    echo "stream_url: ${stream_url}"

    rm -f ${channel}.xml
}

function rec {
    echo "start rec"
    echo "================================="
    echo ${rtmpdump_r}
    echo ${rtmpdump_app}
    echo "================================="

    rtmpdump -v \
        -r ${rtmpdump_r} \
        --app ${rtmpdump_app} \
        --playpath ${rtmpdump_playpath} \
        -W $playerurl \
        -C S:"" -C S:"" -C S:"" -C S:$authtoken \
        --live \
        --stop ${DURATION} | \
        ffmpeg -loglevel quiet -i pipe:0 -acodec libmp3lame -ab 64k "${outdir}/${filename}.mp3"
}

i=0
while :
do
    auth
    if [ $? -eq 0 ]; then
        break
    else
        i=`expr ${i} + 1`
        if [ ${i} -eq 30 ]; then
            echo "failed auth"
            exit 1
        fi
        echo "retry [${i}]"
        sleep 1
    fi
done
get_stream_url
rec
