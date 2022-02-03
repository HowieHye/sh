#!/usr/bin/env bash

## Build 20220126-Alpha-001

## 导入通用变量与函数
dir_shell=/ql/shell
. $dir_shell/share.sh
. $dir_shell/api.sh

## 版本号判断
function version_gt() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; }
function version_le() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" == "$1"; }
function version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }
function version_ge() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"; }
cur_version="$(curl -s --noproxy "*" "http://0.0.0.0:5600/api/system"|jq -r .data|jq -r .version)"

# 定义 json 数据查询工具
def_envs_tool(){
    for i in $@; do
        curl -s --noproxy "*" "http://0.0.0.0:5600/api/envs?searchValue=$i" -H "Authorization: Bearer $token" | jq .data | perl -pe "{s|^\[\|\]$||g; s|\n||g; s|\},$|\}\n|g}"
    done
}

def_json_total(){
    def_envs_tool $1 | jq -r .$2
}

def_json(){
    def_envs_tool $1 | grep "$3" | jq -r .$2
}

def_json_match(){
    cat "$1" | perl -pe '{s|^\[\|\]$||g; s|\n||g; s|\},$|\}\n|g}' | grep "$2" | jq -r .$3
}

def_json_value(){
    cat "$1" | perl -pe "{s|^\[\|\]$||g; s|\n||g; s|\},$|\}\n|g}" | grep "$3" | jq -r .$2
}

def_sub(){
    local i j
    for i in $(def_json_total $1 $2 | awk '/'$3'/{print NR}'); do
        j=$((i - 1));
        echo $j
    done
}

def_sub_value(){
    local line=$(($3 + 1))
    def_json_total $1 $2 | awk 'NR=='$line''
}

## 生成pt_pin清单
gen_pt_pin_array() {
    ## 生成 json 值清单
    gen_basic_value(){
        for i in $@; do
            eval $i='($(def_json_total JD_COOKIE $i | perl -pe "{s| ||g}"))'
        done
    }

    #if version_lt $cur_version 2.11.0; then
    #   tmp_id="_id"
    #else
    #   tmp_id="id"
    #fi

    tmp_id="id"
    [[ $(def_json_total JD_COOKIE $tmp_id) =~ "null" ]] && tmp_id="_id"
    tmp_update_timestamp="updatedAt"
    [[ $(def_json_total JD_COOKIE $tmp_update_timestamp) =~ "null" ]] && tmp_update_timestamp="timestamp"

    gen_basic_value value $tmp_id
    ori_sub=(${!value[@]})
    ori_sn=($(def_json JD_COOKIE value | awk '{print NR}'))
    pin=($(def_json_total JD_COOKIE value | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|}"))
    pt_pin=($(def_json_total JD_COOKIE value | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|}" | awk 'BEGIN{for(i=0;i<10;i++)hex[i]=i;hex["A"]=hex["a"]=10;hex["B"]=hex["b"]=11;hex["C"]=hex["c"]=12;hex["D"]=hex["d"]=13;hex["E"]=hex["e"]=14;hex["F"]=hex["f"]=15;}{gsub(/\+/," ");i=$0;while(match(i,/%../)){;if(RSTART>1);printf"%s",substr(i,1,RSTART-1);printf"%c",hex[substr(i,RSTART+1,1)]*16+hex[substr(i,RSTART+2,1)];i=substr(i,RSTART+RLENGTH);}print i;}'))
    wskey_array=($(def_json_total JD_WSCK value))

    CK_WxPusherUid_dir="$dir_scripts"
    CK_WxPusherUid_file="CK_WxPusherUid.json"
    if [[ -f $CK_WxPusherUid_dir/$CK_WxPusherUid_file ]]; then
        if [[ $(def_json_match "$CK_WxPusherUid_dir/$CK_WxPusherUid_file" '"status": 0') ]]; then
            ori_valid_pin=($(def_json_match "$CK_WxPusherUid_dir/$CK_WxPusherUid_file" '"status": 0' pin))
            ori_invalid_pin=($(cat "$CK_WxPusherUid_dir/$CK_WxPusherUid_file" | perl -pe '{s|^\[\|\]$||g; s|\n||g; s|\},$|\}\n|g}' | grep '"status": 1' | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|}"))
        else
            ori_valid_pin=($(def_envs_tool JD_COOKIE | grep '"status": 0' | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|}"))
            ori_invalid_pin=($(def_envs_tool JD_COOKIE | grep '"status": 1' | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|}"))
        fi
    else
        ori_valid_pin=($(def_envs_tool JD_COOKIE | grep '"status": 0' | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|}"))
        ori_invalid_pin=($(def_envs_tool JD_COOKIE | grep '"status": 1' | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|}"))
    fi
}

#青龙启用/禁用环境变量API
ql_process_env_api() {
    local currentTimeStamp=$(date +%s)
    local id=$1
    local status_code=$2
    [[ $status_code = 0 ]] && process=enable
    [[ $status_code = 1 ]] && process=disable
    local url="http://0.0.0.0:5600/api/envs/$process"

    local api=$(
        curl -s --noproxy "*" "$url?t=$currentTimeStamp" \
            -X 'PUT' \
            -H "Accept: application/json" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json;charset=UTF-8" \
            --data-raw "[\"$id\"]"
    )

    code=$(echo $api | jq -r .code)
    message=$(echo $api | jq -r .message)
    if [[ $code == 200 ]]; then
        if [[ $status_code = 0 ]]; then
            echo -e "并启用"
        elif [[ $status_code = 1 ]]; then
            echo -e "并禁用"
        fi
    else
        if [[ $status_code = 0 ]]; then
            echo -e "但启用失败(${message})"
        elif [[ $status_code = 1 ]]; then
            echo -e "但禁用失败(${message})"
        fi
    fi
}

#青龙更新环境变量API
ql_update_env_api() {
    local currentTimeStamp=$(date +%s)
    local name=$1
    local value=$2
    local id=$3
    local remarks=$4
    local url="http://0.0.0.0:5600/api/envs"

    local api=$(
        curl -s --noproxy "*" "$url?t=$currentTimeStamp" \
            -X 'PUT' \
            -H "Accept: application/json" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json;charset=UTF-8" \
            --data-raw "{\"name\":\"$name\",\"value\":\"$value\",\"$tmp_id\":\"$id\",\"remarks\":\"$remarks\"}"
    )
    code=$(echo $api | jq -r .code)
    message=$(echo $api | jq -r .message)
    if [[ $code == 200 ]]; then
        echo -e "$name -> 更新成功"
    else
        echo -e "$name -> 更新失败(${message})"
    fi
}

## WxPusher 通知 API
WxPusher_notify_api() {
    local appToken=$1
    local content=$2
    local summary=$3
    local uids=$4
    local url="http://wxpusher.zjiecode.com/api/send/message"

    local api=$(
        curl -s --noproxy "*" "$url" \
            -X 'POST' \
            -H "Content-Type: application/json" \
            --data-raw "{\"appToken\":\"$appToken\",\"content\":\"$content\",\"summary\":\"$summary\",\"contentType\":\"2\",\"uids\":[$uids]}"
    )
    code=$(echo $api | jq -r .code)
    msg=$(echo $api | jq -r .msg)
    if [[ $code == 1000 ]]; then
        echo -e "# WxPusher 一对一消息发送成功"
    else
        echo -e "# WxPusher 一对一消息发送处理失败(${message})"
    fi
}

# JSON 字符串特殊符号处理
spc_sym_tr(){
    #echo $1 | perl -pe '{s|(\"\|'\''\|\[\|\]\|{\|}\|\\\|\/\|`)|'\\'\\1|g}'
    echo $1 | perl -pe '{s|(\")|'\\'\\1|g}'
}

## 获取用户昵称 API
Get_NickName() {
    local currentTimeStamp=$(date +%s)
    local cookie=$1
    local url_1="https://me-api.jd.com/user_new/info/GetJDUserInfoUnion"
    local url_2="https://wxapp.m.jd.com/kwxhome/myJd/home.json?&useGuideModule=0&bizId=&brandId=&fromType=wxapp&timestamp=$currentTimeStamp"
    local UA_1="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36 Edg/96.0.1054.62"
    local UA_2="Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.10(0x18000a2a) NetType/WIFI Language/zh_CN"

    local api_1=$(
        curl -s --connect-timeout 20 --retry 3 --noproxy "*" "$url_1" \
            -H "Host: me-api.jd.com" \
            -H "Accept: */*" \
            -H "Connection: keep-alive" \
            -H "Cookie: $cookie" \
            -H "User-Agent: $UA_1" \
            -H "Accept-Language: zh-cn" \
            -H "Referer: https://home.m.jd.com/myJd/newhome.action?sceneval=2&ufc=&" \
            -H "Accept-Encoding:  deflate, br"
    )

    local api_2=$(
        curl -s --connect-timeout 20 --retry 3 --noproxy "*" "$url_2" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -H "Host: wxapp.m.jd.com" \
            -H "Connection: keep-alive" \
            -H "Cookie: $cookie" \
            -H "User-Agent: $UA_2" \
            -H "Referer: https://servicewechat.com/wxa5bf5ee667d91626/161/page-frame.html" \
            -H "Accept-Encoding:  compress,deflate, br"
    )

    retcode=$(echo $api_1 | jq -r .retcode)
    if [[ $retcode == 0 ]]; then
        nickname="$(echo $api_1 | jq -r .data | jq -r .userInfo | jq -r .baseInfo | jq -r .nickname)"
        echo -e "$nickname"
    else
        code=$(echo $api_2 | jq -r .code)
        if [[ $code != 999 ]]; then
            nickname="$(echo $api_2 | jq -r .user | jq -r .petName)"
            echo -e "$nickname"
        fi
    fi
}

## 获取用户状态 API
Get_CK_Status() {
    local cookie=$1
    local url="https://me-api.jd.com/user_new/info/GetJDUserInfoUnion"

    local api=$(
        curl -s --connect-timeout 30 --retry 3 "$url" \
            -H "Cookie: $cookie" \
            -H "Referer: https://home.m.jd.com/myJd/home.action"
    )

    local retcode=$(echo $api | jq -r .retcode)
    if [[ "$retcode" == 0 ]]; then
        return 0
    else
        local retcode=$(echo $api | jq -r .retcode)
        if [[ "$retcode" == 0 ]]; then
            return 0
        elif [[ ! "$retcode" || "$retcode" = "null" ]]; then
            return 2
        else
            return 1
        fi
    fi
}

# 名称处理
Get_Full_Name(){
    local i=$1

    remarks[i]="$(def_json JD_COOKIE remarks "pin=${pin[i]};" | head -1)"

    # wskey 相关值
    wskey_value[i]="$(def_json JD_WSCK value "pin=${pin[i]};" | head -1)"
    wskey_id[i]="$(def_json JD_WSCK $tmp_id "pin=${pin[i]};" | head -1)"
    wskey_remarks[i]="$(def_json JD_WSCK remarks "pin=${pin[i]};" | head -1)"
    local wskey_pin_sub="$(def_sub JD_WSCK value "pin=${pin[i]};")"
    [[ "$wskey_pin_sub" ]] && for j in "$wskey_pin_sub"; do unset wskey_array[j]; done

    # WxPusherUid 相关值
    tmp_Uid_1[i]="$(echo ${remarks[i]} | grep -Eo 'UID_\w{28}')"
    [[ -f $CK_WxPusherUid_dir/$CK_WxPusherUid_file ]] && tmp_Uid_2[i]="$(def_json_value "$CK_WxPusherUid_dir/$CK_WxPusherUid_file" Uid "pin=${pin[i]};")"
    if [[ ${tmp_Uid_1[i]} ]]; then
        Uid[i]="${tmp_Uid_1[i]}"
    elif [[ ${tmp_Uid_2[i]} ]]; then
        Uid[i]="${tmp_Uid_2[i]}"
    else
        Uid[i]=""
    fi

    # 备注名处理
    [[ ${remarks[i]} || ${remarks[i]} != "null" ]] && tmp_remarks_id_1[i]="$(echo ${remarks[i]} | awk -F '@@' '{print $1}')"
    [[ ${wskey_remarks[i]} && ${wskey_remarks[i]} != "null" ]] && tmp_remarks_id_2[i]="${wskey_remarks[i]}"
    # [[ -f $CK_WxPusherUid_dir/$CK_WxPusherUid_file ]] && tmp_remarks_id_3[i]="$(def_json_value "$CK_WxPusherUid_dir/$CK_WxPusherUid_file" 备注 "pin=${pin[i]};")"
    if [[ ${tmp_remarks_id_1[i]} && ${tmp_remarks_id_1[i]} != null ]]; then
        remarks_id[i]="${tmp_remarks_id_1[i]}"
        remarks_name[i]="(${remarks_id[i]})"
    elif [[ ${tmp_remarks_id_2[i]} && ${tmp_remarks_id_2[i]} != null  ]]; then
        remarks_id[i]="${tmp_remarks_id_2[i]}"
        remarks_name[i]="(${remarks_id[i]})"
    else
        remarks_id[i]=""
        remarks_name[i]="(未备注)"
    fi
    tmp_NickName_1[i]=$(Get_NickName "${value[i]}")
    [[ -f $CK_WxPusherUid_dir/$CK_WxPusherUid_file ]] && tmp_NickName_2[i]="$(def_json_value "$CK_WxPusherUid_dir/$CK_WxPusherUid_file" NickName "pin=${pin[i]};")"
    if [[ ${tmp_NickName_1[i]} ]]; then
        NickName[i]="${tmp_NickName_1[i]}"
    elif [[ ${tmp_NickName_2[i]} && ${tmp_NickName_2[i]} != "null" ]]; then
        NickName[i]="${tmp_NickName_2[i]}"
    else
        NickName[i]=""
    fi
    [[ ! ${NickName[i]} || ${NickName[i]} = "null" ]] && UserName[i]=${pt_pin[i]} || UserName[i]=${NickName[i]}
    ori_full_name[i]="【${ori_sn[i]}】${UserName[i]}${remarks_name[i]}"
    full_name[i]="${ori_full_name[i]}"

    if [[ $NICKNAME_REMARK_SYNC = 1 ]]; then
        if [[ ! "${remarks[i]}" =~ "${NickName[i]}" ]]; then
            remarks_ori_id[i]="$(echo ${remarks_id[i]} | awk -F '(' '{print $1}')"
            if [[ ! ${NickName[i]} || ${NickName[i]} = "null" ]]; then
                remarks_id[i]="${remarks_ori_id[i]}(${pt_pin[i]})"
            else
                remarks_id[i]="${remarks_ori_id[i]}(${NickName[i]})"
            fi
        fi
    fi
    remarks_new[i]="${remarks_id[i]}"
}

# 批量检查 Cookie 有效性
verify_ck(){
    # JD_COOKIE 有效性检查
    check_ck(){
        local i=$1
        tmp_status[i]="$(def_json JD_COOKIE status "pin=${pin[i]};")"
        Get_CK_Status ${value[i]}
        if [[ $? = 0 ]]; then
            ck_status[i]="0"
            ck_valid[i]="${full_name[i]}\n"
            ck_valid_sub[i]="$i"
            ck_status_chinese[i]="正常"
            ck_process_chinese[i]="启用"
        elif [[ $? = 1 ]]; then
            ck_status[i]="1"
            ck_invalid[i]="${full_name[i]}\n"
            ck_invalid_sub[i]="$i"
            ck_status_chinese[i]="失效"
            ck_process_chinese[i]="禁用"
        elif [[ $? = 2 ]]; then
            ck_status[i]=""
            ck_unknown_state[i]="${full_name[i]}\n"
            ck_unknown_state_sub[i]="$i"
            ck_status_chinese[i]="因 API 连接失败跳过检测"
        fi
        echo -n "${full_name[i]} ${ck_status_chinese[i]}"
        [[ ${ck_status[i]} ]] && [[ ${ck_status[i]} != ${status[i]} && ${ck_status[i]} != ${tmp_status[i]} ]] && ql_process_env_api $(eval echo \${$tmp_id[i]}) ${ck_status[i]} || echo -e ""
    }

    # JD_WSCK(wskey) 录入情况检查
    check_wskey(){
        local i=$1
        local notify=$2
        if [[ $NOTIFY_WSKEY_NO_EXIST = 1 || $NOTIFY_WSKEY_NO_EXIST = 2 ]]; then
            if [[ ! ${wskey_value[i]} || ${wskey_value[i]} = "null" ]]; then
                ck_none_wskey[i]="${full_name[i]}\n"
                ck_none_wskey_sub[i]="$i"
                [[ $notify = on ]] && echo -e "${full_name[i]} 未录入JD_WSCK(wskey)"
            fi
        fi
    }

    # 账号剩余有效期检查
    check_validity(){
        local i=$1
        local notify=$2
        if [[ ${ck_status[i]} = 0 ]]; then
            timestamp[i]="$(def_json JD_COOKIE $tmp_update_timestamp "pin=${pin[i]};" | head -1)"
            local sys_timestamp[i]=$(date -d "${timestamp[i]}" +%s)
            local cur_sys_timestamp=`date '+%s'`
            local total_validity_period=$((30*24*3600))
            local remain_validity_period=$((total_validity_period-cur_sys_timestamp+sys_timestamp[i]))
            if [[ $remain_validity_period -ge 86400 ]]; then
                local valid_time="$((remain_validity_period/86400))天"
            else
                if [[ $remain_validity_period -ge 3600 ]]; then
                    local valid_time="$((remain_validity_period/3600))小时"
                elif [[ $remain_validity_period -ge 60 ]]; then
                    local valid_time="$((remain_validity_period/60))分钟"
                elif [[ $remain_validity_period -ge 1 ]]; then
                    local valid_time="$remain_validity_period秒"
                fi
                ck_validity_lt_1day[i]="${full_name[i]}\n"
            fi
            if [[ $NOTIFY_VALID_TIME = 1 || $NOTIFY_VALID_TIME = 2 ]]; then
                ck_validity[i]="${full_name[i]} 剩余有效期$valid_time\n"
                [[ $notify = on ]] && echo -e "${full_name[i]} 剩余有效期$valid_time"
            fi
        else
            ck_validity_lt_1day[i]=""
            ck_validity[i]=" "
        fi
    }

    # 生成 CK_WxPusherUid.json 或 CK_WxPusherUid_Sample.json 模板
    wxpusher_json(){
        local i=$1
        local notify=$2
        if [[ ${Uid[i]} ]]; then
            timestamp_s[i]="$(echo ${remarks[i]} | grep -Eo '@@([0-9]{13})' | grep -Eo '[0-9]{13}' | head -1)"
            ori_timestamp_s[i]="${timestamp_s[i]}"
            [[ $CK_WxPusherUid = 1 ]] && [[ ${timestamp_s[i]} ]] && [[ ! ${tmp_Uid_1[i]} ]] && ck_undocked_uid[i]="${full_name[i]}\n"
            [[ ! ${timestamp_s[i]} ]] && timestamp_s[i]=$(echo $[$(date +%s%N)/1000000])
            remarks_new[i]="${remarks_id[i]}@@${timestamp_s[i]}@@${Uid[i]}"
            [[ ! ${tmp_Uid_1[i]} || ! ${ori_timestamp_s[i]} ]] && [[ $CK_WxPusherUid = 1 ]] && echo -n "${full_name[i]} " && ql_update_env_api JD_COOKIE "${value[i]}" $(eval echo \${$tmp_id[i]}) "${remarks_new[i]}"
        fi
        [[ ${ck_undocked_uid[i]} ]] && [[ $notify = on ]] && [[ $CK_WxPusherUid = 1 ]] && echo -e "${full_name[i]} 未成功对接WxPusher UID"
        [[ ! ${Uid[i]} ]] && ck_no_uid[i]="${full_name[i]}\n" && [[ $notify = on ]] && [[ $CK_WxPusherUid = 1 ]] && echo -e "${full_name[i]} 未录入WxPusher UID"
        NickName_Json[i]="$(spc_sym_tr ${NickName[i]})"
        remarks_id_Json[i]="$(spc_sym_tr ${remarks_id[i]})"
        CK_WxPusherUid_Json[i]="{\n\t\"序号\": \"${ori_sn[i]}\",\n\t\"NickName\": \"${NickName_Json[i]}\",\n\t\"JD_COOKIE\": \"${value[i]}\",\n\t\"status\": ${ck_status[i]},\n\t\"pin\": \"${pin[i]}\",\n\t\"备注\": \"${remarks_id_Json[i]}\",\n\t\"pt_pin\": \"${pt_pin[i]}\",\n\t\"Uid\": \"${Uid[i]}\"\n},\n"
    }

    # 同步备注名
    sync_nick_to_ck(){
        # 将昵称更新至 JD_COOKIE 的备注
        if [[ $NICKNAME_REMARK_SYNC = 1 ]]; then
            if [[ ${remarks_id[i]} && ${remarks_id[i]} != "null" ]]; then
                if [[ ! "${remarks[i]}" =~ "${NickName[i]}" ]]; then
                    echo -n "${full_name[i]} "
                    ql_update_env_api JD_COOKIE "${value[i]}" $(eval echo \${$tmp_id[i]}) "${remarks_new[i]}"
                    Get_Full_Name $i
                fi
            fi
        fi

        # 同步 JD_COOKIE 和 JD_WSCK 的同 pin 备注名双向同步
        if [[ $WSKEY_REMARK_SYNC = 1 ]]; then
            if [[ ${remarks_id[i]} && ${remarks_id[i]} != "null" ]]; then
                if [[ ! ${remarks[i]} || ${remarks[i]} = "null" ]]; then
                    echo -n "${full_name[i]} " && ql_update_env_api JD_COOKIE "${value[i]}" $(eval echo \${$tmp_id[i]}) "${remarks_new[i]}"
                    #Get_Full_Name $i
                fi
                if [[ ${wskey_value[i]} && ${wskey_value[i]} != "null" ]] && [[ ${remarks_id[i]} != ${wskey_remarks[i]} ]]; then
                    echo -n "${full_name[i]} " && ql_update_env_api JD_WSCK "${wskey_value[i]}" ${wskey_id[i]} "${remarks_id[i]}"
                    #Get_Full_Name $i
                fi
            fi
        fi
    }

    for i in $@; do
        echo ""
        Get_Full_Name $i
        check_ck $i
        check_wskey $i on
        check_validity $i on
        wxpusher_json $i on
        sync_nick_to_ck $i
    done
}

# 通知内容整理及通知
content_notify(){
    ## 失效账号/重启账号一对一通知
    log_one_to_one(){
        local i=$1
        local process=$2
        local status=$3
        if [[ $(echo $WP_APP_TOKEN_ONE|grep -Eo 'AT_(\w{32})') ]]; then
            if [[ $(echo $MainWP_UID|grep -Eo 'UID_\w{28}') ]] && [[ ${Uid[i]} ]]; then
                local uid="$(echo $MainWP_UID,${Uid[i]} | perl -pe '{s|^|\"|; s|,|\",\"|g; s|$|\"|}')"
            elif [[ ! $(echo $MainWP_UID|grep -Eo 'UID_\w{28}') ]] && [[ ${Uid[i]} ]]; then
                local uid="$(echo ${Uid[i]} | perl -pe '{s|^|\"|; s|$|\"|}')"
            elif [[ $(echo $MainWP_UID|grep -Eo 'UID_\w{28}') ]] && [[ ! ${Uid[i]} ]]; then
                local uid="$(echo $MainWP_UID | perl -pe '{s|^|\"|; s|$|\"|}')"
            fi
            if [[ "$uid" ]]; then
                local content_1="Cookie $process通知<br><br>${full_name[i]} 账号$status并$process"
                [[ ${ck_none_wskey[i]} ]] && local content_2="，未录入 JD_WSCK(wskey)"
                [[ ${ck_undocked_uid[i]} ]] && local content_3="，WxPusher 未对接成功"
                [[ ${ck_no_uid[i]} ]] && local content_4="，未录入 WxPusher UID"
                local summary="$content_1$content_2$content_3$content_4"
                local content="$summary<br><br><br>$ExNotify_Content"
                WxPusher_notify_api $WP_APP_TOKEN_ONE "$content" "$summary" "$uid"
            fi
        fi
    }

    # 导出最终账号有效性结果并一对一通知
    export_valid_result(){
        local i=$1
        if [[ ${final_status[i]} = 0 ]]; then
            ck_status[i]="0"
            ck_valid[i]="${full_name[i]}\n"
            ck_valid_sub[i]="$i"
            ck_status_chinese[i]="正常"
            ck_process_chinese[i]="启用"
            if [[ ! ${status_last[i]} ]]; then
                ck_added[i]="${full_name[i]}\n"
                ck_added_sub[i]="$i"
                log_one_to_one $i "${ck_process_chinese[i]}" "${ck_status_chinese[i]}"
            elif [[ ${final_status[i]} != ${status_last[i]} ]]; then
                ck_enabled[i]="${full_name[i]}\n"
                ck_enabled_sub[i]="$i"
                log_one_to_one $i "${ck_process_chinese[i]}" "${ck_status_chinese[i]}"
            fi
        elif [[ ${final_status[i]} = 1 ]]; then
            ck_status[i]="1"
            ck_invalid[i]="${full_name[i]}\n"
            ck_invalid_sub[i]="$i"
            ck_status_chinese[i]="失效"
            ck_process_chinese[i]="禁用"
            if [[ ${final_status[i]} != ${status_last[i]} ]]; then
                ck_disabled[i]="${full_name[i]}\n"
                ck_disabled_sub[i]="$i"
                log_one_to_one $i "${ck_process_chinese[i]}" "${ck_status_chinese[i]}"
            fi
        fi
    }

    # 整理通知内容
    sort_notify_content(){
        print_array(){
            local array=$1
            echo ${array[@]}|perl -pe '{s|\\n[\s]+|\\n|g}'
        }

        echo -e "# 正在整理通知内容，请耐心等待 ...\n"
        gen_pt_pin_array
        for i in ${!value[@]}; do
            # 获取上次 JD_COOKIE 的检测状态
            if [[ -f $CK_WxPusherUid_dir/$CK_WxPusherUid_file ]]; then
                if [[ $(def_json_match "$CK_WxPusherUid_dir/$CK_WxPusherUid_file" '"status": 0') ]]; then
                    status_last[i]="$(def_json_value "$CK_WxPusherUid_dir/$CK_WxPusherUid_file" status "pin=${pin[i]};")"
                else
                    status_last[i]=${status[i]}
                fi
            else
                status_last[i]=${status[i]}
            fi
            final_status[i]="$(def_json JD_COOKIE status "pin=${pin[i]};")"
            [[ "${final_status[i]}" == "${status_last[i]}" ]] && [[ "${final_status[i]}" == "${ck_status[i]}" ]] && continue
            Get_Full_Name $i
            export_valid_result $i
            check_wskey $i
            check_validity $i
            wxpusher_json $i
            sync_nick_to_ck $i
        done

        invalid_all="$(print_array "${ck_invalid[*]}")"
        [[ $invalid_all ]] && notify_content_invalid_all="失效账号(共${#ck_invalid[*]}个)：\n$invalid_all\n"
        content_1=$notify_content_invalid_all

        ck_disabled_all="$(print_array "${ck_disabled[*]}")"
        [[ $ck_disabled_all ]] && notify_content_ck_disabled_all="本次禁用账号(共${#ck_disabled[*]}个)：\n$ck_disabled_all\n"
        content_2=$notify_content_ck_disabled_all

        validity_lt_1day_all="$(print_array "${ck_validity_lt_1day[*]}")"
        [[ $validity_lt_1day_all ]] && notify_content_validity_lt_1day_all="有效期不足 1 天的账号(共${#ck_validity_lt_1day[*]}个)：\n$validity_lt_1day_all\n"
        [[ $NOTIFY_VALID_TIME = 1 ]] && content_3=$notify_content_validity_lt_1day_all

        no_wsck_all="$(print_array "${ck_none_wskey[*]}")"
        [[ $no_wsck_all ]] && notify_content_no_wsck_all="未录入 JD_WSCK(wskey) 的账号(共${#ck_none_wskey[*]}个)：\n$no_wsck_all\n"
        [[ $NOTIFY_WSKEY_NO_EXIST = 1 ]] && content_4=$notify_content_no_wsck_all

        ck_undocked_uid_all="$(print_array "${ck_undocked_uid[*]}")"
        [[ $ck_undocked_uid_all ]] && notify_content_ck_undocked_uid_all="WxPusher 未对接成功的账号(共${#ck_undocked_uid[*]}个)：\n$ck_undocked_uid_all\n"
        [[ $CK_WxPusherUid = 1 ]] && content_5=$notify_content_ck_undocked_uid_all

        ck_no_uid_all="$(print_array "${ck_no_uid[*]}")"
        [[ $ck_no_uid_all ]] && notify_content_ck_no_uid_all="未录入 WxPusher UID 的账号：(共${#ck_no_uid[*]}个)\n$ck_no_uid_all\n"
        [[ $CK_WxPusherUid = 1 ]] && content_6=$notify_content_ck_no_uid_all

        ck_added_all="$(print_array "${ck_added[*]}")"
        [[ $ck_added_all ]] && notify_content_ck_added_all="本次新增账号(共${#ck_added[*]}个)：\n$ck_added_all\n"
        [[ $NOTIFY_VALID_CK_TYPE = 1 ]] && content_7=$notify_content_ck_added_all

        ck_enabled_all="$(print_array "${ck_enabled[*]}")"
        [[ $ck_enabled_all ]] && notify_content_ck_enabled_all="本次启用账号(共${#ck_enabled[*]}个)：\n$ck_enabled_all\n"
        [[ $NOTIFY_VALID_CK_TYPE = 1 ]] && content_8=$notify_content_ck_enabled_all

        validity_all="$(print_array "${ck_validity[*]}")"
        [[ $validity_all ]] && notify_content_validity="预测账号有效期(共${#ck_validity[*]}个)：\n$validity_all\n"
        [[ $NOTIFY_VALID_TIME = 1 ]] && content_9=$notify_content_validity

        valid_all="$(print_array "${ck_valid[*]}")"
        [[ $valid_all ]] && notify_content_valid_all="正常账号(共${#ck_valid[*]}个)：\n$valid_all\n"
        [[ $NOTIFY_VALID_CK_TYPE = 1 ]] && content_10=$notify_content_valid_all

        content_11=$ExNotify_Content

        CK_WxPusherUid_Json_All="$(print_array "${CK_WxPusherUid_Json[*]}" | perl -pe '{s|,\\n$|\\n|g; s|{\\n|  {\\n|g; s|\\n}|\\n  }|g}')"
        CK_WxPusherUid_Json_content="[\n$CK_WxPusherUid_Json_All]"

        # 账号有效性检测结果与上次检测结果一致的处理
        valid_pin=($(def_envs_tool JD_COOKIE | grep '"status": 0' | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|}"))
        invalid_pin=($(def_envs_tool JD_COOKIE | grep '"status": 1' | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|}"))
        if [[ ${#invalid_pin[@]} -gt 0 ]]; then
            if [[ $NOTIFY_SKIP_SAME_CONTENT = 1 ]] && [[ "${invalid_pin[@]}" == "${ori_invalid_pin[@]}" ]]; then
                echo -e "# 失效账号与上次检测结果一致，本次不推送。\n"
                content_1=""
            fi
        fi
        if [[ ${#valid_pin[@]} -gt 0 ]]; then
            if [[ $NOTIFY_SKIP_SAME_CONTENT = 1 && "${valid_pin[@]}" == "${ori_valid_pin[@]}" ]]; then
                echo -e "# 有效账号与上次检测结果一致，本次不推送。\n"
                content_10=""
            fi
        fi

        display_content="$notify_content_invalid_all$notify_content_ck_disabled_all$notify_content_ck_enabled_all$notify_content_ck_added_all$notify_content_validity_lt_1day_all$notify_content_no_wsck_all$notify_content_ck_undocked_uid_all$notify_content_ck_no_uid_all$notify_content_valid_all$notify_content_validity"
        notify_content="$content_1$content_2$content_3$content_4$content_5$content_6$content_7$content_8$content_9$content_10"
    }

    # 推送通知
    sort_notify_content
    echo -e "$display_content"
    [[ $notify_content ]] && echo -e "# 推送通知..." && notify "Cookie 状态通知" "$notify_content\n\n$ExNotify_Content" >/dev/null 2>&1
    if [[ $(echo $WP_APP_TOKEN_ONE|grep -Eo 'AT_(\w{32})') ]] && [[ $(echo $MainWP_UID|grep -Eo 'UID_\w{28}') ]]; then
        WxPusher_notify_content="Cookie 状态通知<br><br>$(echo $display_content | perl -pe '{s|\\n|<br>|g}')<br><br>$ExNotify_Content"
        uids="$(echo $MainWP_UID | perl -pe '{s|^|\"|; s|$|\"|}')"
        WxPusher_notify_api $WP_APP_TOKEN_ONE "$WxPusher_notify_content" "Cookie 状态通知" "$uids"
    fi
}

# 主站链接数组
host_url_array=(
  https://raw.fastgit.org
  https://raw.githubusercontent.com
)

# 筛选主站链接
define_url(){
    for i in $@; do
        local url="$i"
        local api=$(
            curl -sI --connect-timeout 30 --retry 3 --noproxy "*" -o /dev/null -s -w %{http_code} "$url"
        )
        code=$(echo $api)
        [[ $code == 200 || $code == 301 ]] && echo "$url" && break
    done
}

## 文件下载工具
download_file(){
    get_remote_filesize(){
        local url="$1"
        curl -sI --connect-timeout 30 --retry 3 --noproxy "*" "$url" | grep -i Content-Length | awk '{print $2}'
    }

    get_local_filesize(){
       stat -c %s $1
    }

    get_md5(){
        md5sum $1 | cut -d ' ' -f1
    }

    local url="$1"
    local file_path="$2"
    file="${url##*/}"

    curl -C - -s --connect-timeout 30 --retry 3 --noproxy "*" "$url" -o $file_path/tmp_$file
    if [[ -f "$file_path/tmp_$file" ]]; then
        if [[ $(get_remote_filesize $url) -eq $(get_local_filesize $file_path/tmp_$file ) ]]; then
            if [[ -f "$file_path/$file" ]]; then
                [[ "$(get_md5 $file_path/$file)" != "$(get_md5 $file_path/tmp_$file)" ]] && mv -f $file_path/tmp_$file $file_path/$file || rm -rf $file_path/tmp_$file
            else
                mv -f $file_path/tmp_$file $2/$file
            fi
        fi
    fi
}

## 选择python3还是node
define_program() {
    local first_param=$1
    if [[ $first_param == *.js ]]; then
        which_program="node"
    elif [[ $first_param == *.py ]]; then
        which_program="python3"
    elif [[ $first_param == *.sh ]]; then
        which_program="bash"
    elif [[ $first_param == *.ts ]]; then
        which_program="ts-node-transpile-only"
    else
        which_program=""
    fi
}

## 检测到失效账号，或还未转换为 JD_COOKIE 的 JD_WSCK(wskey)，则搜索或下载wskey转换脚本进行转换
wsck_to_ck(){
    progress_wskey_scr(){
        wskey_scr="$(find $dir_scripts -type f -name *wskey*.py | head -1)"
        if [[ -f $wskey_scr ]]; then
            echo -e "# 已搜索到 wskey 转换脚本，开始执行 wskey 转换 ..."
            define_program $wskey_scr
            $which_program $wskey_scr
            echo -e ""
        else
            if [[ $DOWNLOAD_WSKEY_SCR = 1 ]]; then
                echo -e "# 未搜索到脚本，开始下载 wskey 转换脚本 ..."
                [[ ! $WSKEY_SCR_URL ]] && host_url="$(define_url ${host_url_array[@]})" && WSKEY_SCR_URL="$host_url/Zy143L/wskey/main/wskey.py"
                download_file "$WSKEY_SCR_URL" $dir_scripts >/dev/null 2>&1
                wskey_scr="$file"
                if [[ -f "$dir_scripts/$wskey_scr" ]]; then
                   echo -e "# wskey 转换脚本下载成功，开始执行 wskey 转换 ..."
                   define_program "$dir_scripts/$wskey_scr"
                   $which_program "$dir_scripts/$wskey_scr"
                   echo -e ""
                else
                   echo -e "# wskey 转换脚本下载失败，跳过 wskey 转换 ..."
                   echo -e ""
                fi
            else
                echo -e "# 未搜索到 wskey 转换脚本，跳过 wskey 转换 ..."
                echo -e ""
            fi
        fi
    }

    if [[ $WSKEY_TO_CK = 1 ]] && [[ ${#wskey_value[@]} -gt 0 ]]; then
        if [[ ${#ck_invalid[@]} -gt 0 ]]; then
            echo -e "# 检测到失效账号，开始搜索 wskey 转换脚本 ..."
            progress_wskey_scr
        elif [[ ${#wskey_array[@]} -gt 0 ]]; then
            echo -e "# 检测到还未转换 JD_COOKIE 的 JD_WSCK(wskey)，开始搜索 wskey 转换脚本 ..."
            progress_wskey_scr
        fi
    fi
}

echo -e ""
echo -n "# 开始检查账号有效性"
[[ $NOTIFY_VALID_TIME = 1 || $NOTIFY_VALID_TIME = 2 ]] && echo -e "，预测账号有效期谨供参考 ..." || echo -e " ..."
gen_pt_pin_array
gen_basic_value status
verify_ck ${!value[@]}
echo ""
wsck_to_ck
content_notify

#[[ $CK_WxPusherUid = 1 ]] && echo -e "$CK_WxPusherUid_Json_content" > $CK_WxPusherUid_dir/$CK_WxPusherUid_file
echo -e "$CK_WxPusherUid_Json_content" > $CK_WxPusherUid_dir/$CK_WxPusherUid_file
