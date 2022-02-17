#!/usr/bin/env bash

## Build 20220214-001-test

## 导入通用变量与函数
dir_shell=/ql/shell
. $dir_shell/share.sh
. $dir_shell/api.sh

# 定义 json 数据查询工具
def_envs_tool(){
    for i in $@; do
        curl -s --noproxy "*" "http://0.0.0.0:5600/api/envs?searchValue=$i" -H "Authorization: Bearer $token" | jq .data | perl -pe "{s|^\[\|\]$||g; s|\n||g; s|\},$|\}\n|g}"
    done
}

def_envs_match(){
    def_envs_tool $1 | grep "$2" | jq -r .$3
}

def_json_match(){
    cat "$1" | perl -pe '{s|^\[\|\]$||g; s|\n||g; s|\},$|\}\n|g}' | grep "$2" | jq -r .$3
}

def_json_value(){
    cat "$1" | perl -pe "{s|^\[\|\]$||g; s|\n||g; s|\},$|\}\n|g}" | grep "$3" | jq -r .$2
}

## WxPusher 通知 API
WxPusher_notify_api() {
    local appToken=$1
    local content=$2
    local summary=$3
    local uids=$4
    local frontcontent=$5
    local url="http://wxpusher.zjiecode.com/api/send/message"

    [[ ${#summary} -gt 100 ]] && local summary="${summary: 0: 90} ……"

    local api=$(
        curl -s --noproxy "*" "$url" \
            -X 'POST' \
            -H "Content-Type: application/json" \
            --data-raw "{\"appToken\":\"$appToken\",\"content\":\"$content\",\"summary\":\"$summary\",\"contentType\":\"2\",\"uids\":[$uids]}"
    )
    code=$(echo $api | jq -r .code)
    msg=$(echo $api | jq -r .msg)
    if [[ $code == 1000 ]]; then
        echo -e "#$frontcontent WxPusher 消息发送成功(${uids})\n"
    else
        [[ ! $msg ]] && msg="访问 API 超时"
        echo -e "#$frontcontent WxPusher 消息发送处理失败(${msg})\n"
    fi
}

Notify_to_Public(){
    CK_WxPusherUid_dir="$dir_scripts"
    CK_WxPusherUid_file="CK_WxPusherUid.json"

    if [[ $Filter_Disabled_Variable = true ]]; then
        if [[ $WxPusher_UID_src = 1 ]]; then
            WxPusher_UID_Array=($(def_envs_match JD_COOKIE '"status": 0' remarks | grep -Eo 'UID_\w{28}'))
        elif [[ $WxPusher_UID_src = 2 ]]; then
            WxPusher_UID_Array=($(def_json_match "$CK_WxPusherUid_dir/$CK_WxPusherUid_file" '"status": 0' Uid | grep -Eo 'UID_\w{28}'))
        fi
    elif [[ $Filter_Disabled_Variable = false ]]; then
        if [[ $WxPusher_UID_src = 1 ]]; then
            WxPusher_UID_Array=($(def_envs_tool JD_COOKIE remarks | grep -Eo 'UID_\w{28}'))
        elif [[ $WxPusher_UID_src = 2 ]]; then
            WxPusher_UID_Array=($(def_json_value "$CK_WxPusherUid_dir/$CK_WxPusherUid_file" Uid | grep -Eo 'UID_\w{28}'))
        fi
    fi

    local content=$(echo "$NOTICE_CONTENT" | perl -pe '{s|(\")|'\\'\\1|g; s|\n|<br>|g}')
    local summary=$(echo "$NOTICE_SUMMARY" | perl -pe '{s|(\")|'\\'\\1|g; s|\n|<br>|g}')
    if [[ ${#WxPusher_UID_Array[@]} -gt 0 ]]; then
        uid="$(echo "${WxPusher_UID_Array[*]}" | perl -pe '{s|^|\"|; s| |\",\"|g; s|$|\"|}')"
        if [[ ${content} && ${summary} ]]; then
            echo -e "# 公告摘要：$summary"
            echo -e "# 公告正文：$content"            
            WxPusher_notify_api $WP_APP_TOKEN_ONE "$content" "$summary" "$uid"
        else
            if [[ ! ${summary} ]]; then
                echo -e "# 未填写公告摘要，请检查后重试！"
            fi
            if [[ ! ${content} ]]; then
                echo -e "# 未填写公告正文，请检查后重试！"
            fi
        fi
    else
        echo -e "# 未找到 WxPusher UID，请检查后重试！"
    fi
}

Notify_to_Public