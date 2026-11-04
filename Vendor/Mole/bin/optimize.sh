#!/bin/bash
# Mole - Optimize command.
# Runs system maintenance tasks.
# Supports dry-run where applicable.

set -euo pipefail

# User state and installed tools must never run with inherited root privileges.
# Individual maintenance operations request administrator access themselves.
if [[ "$EUID" -eq 0 ]]; then
    printf '%s\n' 'Run Mole without sudo; it requests administrator access when needed.' >&2
    exit 1
fi

# Fix locale issues.
export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"

# Clean temp files on exit.
trap cleanup_temp_files EXIT INT TERM
source "$SCRIPT_DIR/lib/core/sudo.sh"
source "$SCRIPT_DIR/lib/optimize/diagnostics.sh"
source "$SCRIPT_DIR/lib/optimize/maintenance.sh"
source "$SCRIPT_DIR/lib/optimize/catalog.sh"
source "$SCRIPT_DIR/lib/optimize/tasks.sh"
source "$SCRIPT_DIR/lib/check/health_json.sh"
source "$SCRIPT_DIR/lib/manage/whitelist.sh"

print_header() {
    printf '\n'
    echo -e "${PURPLE_BOLD}$(mole_t 'Optimize' '系统优化')${NC}"
}

# Extract a simple numeric value from JSON by key without a jq dependency.
json_get_value() {
    local json="$1"
    local key="$2"
    local value
    value=$(echo "$json" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*[0-9.]*" | head -1 | sed 's/.*:[[:space:]]*//')
    echo "${value:-0}"
}

# Validate JSON has expected structure (basic check).
json_validate() {
    local json="$1"
    # Check for required keys
    [[ "$json" == *'"memory_used_gb"'* ]] &&
        [[ "$json" == *'"optimizations"'* ]] &&
        [[ "$json" == *'{'* ]] && [[ "$json" == *'}'* ]]
}

show_optimization_summary() {
    local total
    total=$(optimize_outcome_total)
    if ((total == 0)); then
        return
    fi

    local summary_title
    local -a summary_details=()
    local applied unchanged skipped unavailable attention failed
    applied=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_APPLIED")
    unchanged=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_UNCHANGED")
    skipped=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_SKIPPED")
    unavailable=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_UNAVAILABLE")
    attention=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_ATTENTION")
    failed=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_FAILED")

    local -a outcome_parts=()
    [[ $unchanged -gt 0 ]] && outcome_parts+=("$unchanged $(mole_t 'unchanged' '项无需处理')")
    [[ $skipped -gt 0 ]] && outcome_parts+=("$skipped $(mole_t 'skipped' '项已跳过')")
    [[ $unavailable -gt 0 ]] && outcome_parts+=("$unavailable $(mole_t 'unavailable' '项不可用')")
    [[ $attention -gt 0 ]] && outcome_parts+=("$attention $(mole_t 'need attention' '项需要关注')")
    [[ $failed -gt 0 ]] && outcome_parts+=("$failed $(mole_t 'failed' '项失败')")

    local outcome_line=""
    if [[ ${#outcome_parts[@]} -gt 0 ]]; then
        outcome_line="${outcome_parts[0]}"
        local index
        for ((index = 1; index < ${#outcome_parts[@]}; index++)); do
            outcome_line+=" | ${outcome_parts[$index]}"
        done
    fi

    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        summary_title=$(mole_t 'Dry Run Complete, No Changes Made' '预览完成，未修改任何内容')
        summary_details+=("$(mole_t 'Would apply' '将执行') ${YELLOW}${applied}${NC} $(mole_t 'optimizations' '项优化')")
        [[ -n "$outcome_line" ]] && summary_details+=("$outcome_line")
        summary_details+=("$(mole_t 'Run without' '去掉') ${YELLOW}--dry-run${NC} $(mole_t 'to apply these changes' '后重新运行即可执行')")
    else
        summary_title=$(mole_t 'Optimization Complete' '系统优化完成')

        local cache_kb="${OPTIMIZE_CACHE_CLEANED_KB:-0}"
        local db_count="${OPTIMIZE_DATABASES_COUNT:-0}"
        local config_count="${OPTIMIZE_CONFIGS_REPAIRED:-0}"

        local key_stat=""
        if [[ "$cache_kb" =~ ^[0-9]+$ ]] && [[ "$cache_kb" -gt 0 ]]; then
            local cache_human
            cache_human=$(bytes_to_human "$((cache_kb * 1024))")
            key_stat="${cache_human} $(mole_t 'cache cleaned' '缓存已清理')"
        elif [[ "$db_count" =~ ^[0-9]+$ ]] && [[ "$db_count" -gt 0 ]]; then
            key_stat="${db_count} $(mole_t 'databases optimized' '个数据库已优化')"
        elif [[ "$config_count" =~ ^[0-9]+$ ]] && [[ "$config_count" -gt 0 ]]; then
            key_stat="${config_count} $(mole_t 'configs repaired' '个配置已修复')"
        fi

        if [[ -n "$key_stat" ]]; then
            summary_details+=("$(mole_t 'Applied' '已执行') ${GREEN}${applied}${NC} $(mole_t 'optimizations' '项优化'), ${key_stat}")
        else
            summary_details+=("$(mole_t 'Applied' '已执行') ${GREEN}${applied}${NC} $(mole_t 'optimizations' '项优化')")
        fi

        [[ -n "$outcome_line" ]] && summary_details+=("$outcome_line")
        if [[ $attention -gt 0 || $failed -gt 0 ]]; then
            summary_details+=("$(mole_t 'Review the warnings above' '请检查上方警告')")
        else
            summary_details+=("$(mole_t 'Optimization pass complete' '优化流程已完成')")
        fi
    fi

    print_summary_block "$summary_title" "${summary_details[@]}"
}

show_system_health() {
    local health_json="$1"

    local mem_used=$(json_get_value "$health_json" "memory_used_gb")
    local mem_total=$(json_get_value "$health_json" "memory_total_gb")
    local disk_used=$(json_get_value "$health_json" "disk_used_gb")
    local disk_total=$(json_get_value "$health_json" "disk_total_gb")
    local disk_percent=$(json_get_value "$health_json" "disk_used_percent")
    local uptime=$(json_get_value "$health_json" "uptime_days")

    mem_used=${mem_used:-0}
    mem_total=${mem_total:-0}
    disk_used=${disk_used:-0}
    disk_total=${disk_total:-0}
    disk_percent=${disk_percent:-0}
    uptime=${uptime:-0}

    # printf parses float arguments with the locale's decimal separator, so
    # comma-decimal locales reject dot values like "5.70" (#1220). Round in
    # C-locale awk and print plain strings to avoid float parsing entirely.
    local rounded
    rounded=$(LC_ALL=C awk -v mu="$mem_used" -v mt="$mem_total" -v du="$disk_used" -v dt="$disk_total" -v ut="$uptime" \
        'BEGIN { printf "%.0f %.0f %.0f %.0f %.0f", mu, mt, du, dt, ut }' 2> /dev/null || echo "0 0 0 0 0")
    read -r mem_used mem_total disk_used disk_total uptime <<< "$rounded"

    printf "${ICON_ADMIN} $(mole_t 'System' '系统')  %s/%s GB RAM | %s/%s GB $(mole_t 'Disk' '磁盘') | $(mole_t 'Uptime' '运行时间') %sd\n" \
        "$mem_used" "$mem_total" "$disk_used" "$disk_total" "$uptime"
}

announce_action() {
    local name="$1"
    name=$(mole_optimize_task_text "$name")

    if [[ "${FIRST_ACTION:-true}" == "true" ]]; then
        export FIRST_ACTION=false
    else
        echo ""
    fi
    echo -e "${BLUE}${ICON_ARROW} ${name}${NC}"
}

cleanup_all() {
    local exit_status="${1:-0}"
    stop_inline_spinner 2> /dev/null || true
    stop_sudo_session
    cleanup_temp_files
    # Log session end
    local applied=0
    local failed=0
    if declare -F optimize_outcome_count > /dev/null; then
        applied=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_APPLIED")
        failed=$(optimize_outcome_count "$MOLE_OPTIMIZE_OUTCOME_FAILED")
        local failed_action
        while IFS= read -r failed_action; do
            [[ -n "$failed_action" ]] || continue
            log_operation "optimize" "TASK_FAILED" "$failed_action" "task outcome"
        done < <(optimize_failed_actions)
        # Applied tasks changed system state (SQLite, defaults, Spotlight,
        # DNS); a preview applied nothing, so it records none.
        if [[ "${MOLE_DRY_RUN:-0}" != "1" ]]; then
            local applied_action
            while IFS= read -r applied_action; do
                [[ -n "$applied_action" ]] || continue
                log_operation "optimize" "REBUILT" "$applied_action" "task outcome"
            done < <(optimize_actions_with_outcome "$MOLE_OPTIMIZE_OUTCOME_APPLIED")
        fi
    fi
    if [[ "$exit_status" -ne 0 && "$failed" -eq 0 ]]; then
        local failure_action="session"
        [[ "$exit_status" -eq 130 ]] && failure_action="interrupted"
        log_operation "optimize" "TASK_FAILED" "$failure_action" "exit status $exit_status"
    fi
    log_operation_session_end "optimize" "$applied" "0"
}

handle_interrupt() {
    trap - EXIT
    cleanup_all 130
    exit 130
}

main() {
    # Set current command for operation logging
    export MOLE_CURRENT_COMMAND="optimize"

    local health_json
    for arg in "$@"; do
        case "$arg" in
            "--help" | "-h")
                show_optimize_help
                exit 0
                ;;
            "--debug")
                export MO_DEBUG=1
                ;;
            "--dry-run" | "-n")
                export MOLE_DRY_RUN=1
                ;;
            "--whitelist")
                manage_whitelist "optimize"
                exit 0
                ;;
            *)
                echo "Unknown optimize option: $arg" >&2
                echo "Use 'mo optimize --help' for supported options." >&2
                exit 1
                ;;
        esac
    done

    log_operation_session_start "optimize"

    trap 'cleanup_all "$?"' EXIT
    trap handle_interrupt INT TERM

    if [[ -t 1 ]]; then
        clear_screen
    fi
    print_header

    # Dry-run indicator.
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        echo -e "${YELLOW}${ICON_DRY_RUN} $(mole_t 'DRY RUN MODE' '预览模式')${NC}, $(mole_t 'No files will be modified' '不会修改任何文件')\n"
    fi

    if ! command -v bc > /dev/null 2>&1; then
        echo -e "${YELLOW}${ICON_ERROR}${NC} $(mole_t 'Missing dependency' '缺少依赖'): bc"
        echo -e "${GRAY}$(mole_t 'Install with' '安装命令'): ${GREEN}brew install bc${NC}"
        exit 1
    fi

    if [[ -t 1 ]]; then
        start_inline_spinner "$(mole_t 'Collecting system info...' '正在收集系统信息...')"
    fi

    if ! health_json=$(generate_health_json 2> /dev/null); then
        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi
        echo ""
        log_error "$(mole_t 'Failed to collect system health data' '无法收集系统健康数据')"
        exit 1
    fi

    if ! json_validate "$health_json"; then
        if [[ -t 1 ]]; then
            stop_inline_spinner
        fi
        echo ""
        log_error "$(mole_t 'Invalid system health data format' '系统健康数据格式无效')"
        echo -e "${GRAY}${ICON_REVIEW}${NC} $(mole_t 'Check if awk, sysctl, and df commands are available' '请检查 awk、sysctl 和 df 命令是否可用')"
        exit 1
    fi

    if [[ -t 1 ]]; then
        stop_inline_spinner
    fi

    load_whitelist "optimize" || exit 1
    if [[ ${#CURRENT_WHITELIST_PATTERNS[@]} -gt 0 ]]; then
        local count=${#CURRENT_WHITELIST_PATTERNS[@]}
        if [[ $count -le 3 ]]; then
            local patterns_list=$(
                IFS=', '
                echo "${CURRENT_WHITELIST_PATTERNS[*]}"
            )
            echo -e "${ICON_ADMIN} $(mole_t 'Active Whitelist' '已启用白名单'): ${patterns_list}"
        fi
    fi

    show_system_health "$health_json"

    run_optimize_diagnostics

    echo ""
    # Track sudo availability so individual tasks can skip cleanly when admin
    # access was denied. Without this, every sudo task re-prompts for the
    # password and half-runs after a refusal. Default true in dry-run so the
    # task list still expands fully for inspection.
    export MOLE_OPTIMIZE_SUDO_AVAILABLE="false"
    if [[ "${MOLE_DRY_RUN:-0}" == "1" ]]; then
        MOLE_OPTIMIZE_SUDO_AVAILABLE="true"
    elif ensure_sudo_session "$(mole_t 'System optimization requires admin access' '系统优化需要管理员权限')"; then
        MOLE_OPTIMIZE_SUDO_AVAILABLE="true"
    else
        opt_msg "$(mole_t 'Skipping sudo-required optimizations: admin access not granted' '跳过需要管理员权限的优化项：未获得授权')"
    fi

    export FIRST_ACTION=true
    optimize_outcomes_reset
    local index action health_name
    for ((index = 0; index < ${#MOLE_OPTIMIZE_ACTIONS[@]}; index++)); do
        action=${MOLE_OPTIMIZE_ACTIONS[$index]}
        health_name=${MOLE_OPTIMIZE_HEALTH_NAMES[$index]}
        announce_action "$health_name"
        execute_optimization "$action"
    done

    if [[ "$(optimize_outcome_total)" -ne ${#MOLE_OPTIMIZE_ACTIONS[@]} ]]; then
        log_error "$(mole_t 'Optimize task outcomes are incomplete' '优化任务结果不完整')"
        return 1
    fi

    show_optimization_summary

    printf '\n'
    optimize_outcomes_succeeded
}

main "$@"
