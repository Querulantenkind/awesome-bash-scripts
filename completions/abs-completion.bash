#!/bin/bash

################################################################################
# Bash Completion for Awesome Bash Scripts
# Version: 1.0.0
#
# To use this completion, source it in your .bashrc:
#   source /path/to/abs-completion.bash
#
# Or install system-wide:
#   sudo cp abs-completion.bash /etc/bash_completion.d/
################################################################################

# Main completion function
_abs_complete() {
    local cur prev words cword
    _init_completion || return
    
    # Common options for all scripts
    local common_opts="-h --help -v --verbose -q --quiet"
    
    # Get script name (remove abs- prefix)
    local script_name="${words[0]#abs-}"
    
    # Script-specific completions
    case "$script_name" in
        system-monitor)
            local opts="$common_opts --once --watch --interval --network --processes --disk --cpu-alert --mem-alert --disk-alert --json --log-file --config"
            ;;
        service-monitor)
            local opts="$common_opts --service --all --auto-restart --notify-desktop --notify-email --check-interval --max-retries --json --log-file --config"
            ;;
        log-analyzer)
            local opts="$common_opts --file --follow --pattern --error --warning --http --stats --json --time-from --time-to --ip-stats"
            ;;
        network-monitor)
            local opts="$common_opts --interface --duration --ports --bandwidth --once"
            ;;
        backup-manager)
            local opts="$common_opts --backup --restore --list --verify --type --source --destination --compression --encrypt --exclude --rotation --dry-run"
            ;;
        database-backup)
            local opts="$common_opts --type --host --port --user --password --database --output-dir --compression --encrypt --rotation --all-databases"
            ;;
        sync-backup)
            local opts="$common_opts --source --destination --exclude --bandwidth-limit --checksum --dry-run --delete --remote --ssh-key"
            ;;
        file-organizer)
            local opts="$common_opts --directory --by-type --by-date --by-size --recursive --move --copy --undo --dry-run"
            ;;
        duplicate-finder)
            local opts="$common_opts --directory --algorithm --min-size --keep --interactive --auto-delete --dry-run"
            ;;
        bulk-renamer)
            local opts="$common_opts --directory --find --replace --prefix --suffix --lowercase --uppercase --sequential --undo --dry-run"
            ;;
        system-info)
            local opts="$common_opts --hardware --software --network --all --json --csv --save"
            ;;
        package-cleanup)
            local opts="$common_opts --orphans --cache --logs --all --dry-run"
            ;;
        security-audit)
            local opts="$common_opts --users --permissions --network --services --firewall --all --json --report"
            ;;
        firewall-manager)
            local opts="$common_opts --enable --disable --status --allow --deny --delete --profile --port --protocol"
            ;;
        port-scanner)
            local opts="$common_opts --ports --timeout --threads --tcp --udp --all --common --top --banner --service --output --format --stealth"
            ;;
        bandwidth-monitor)
            local opts="$common_opts --interface --duration --interval --unit --processes --connections --top --alert --output --format --graph"
            ;;
        password-generator)
            local opts="$common_opts --length --number --type --strength --include --exclude --no-uppercase --no-lowercase --no-numbers --no-symbols --words --delimiter --copy --qrcode --output --format"
            ;;
        system-benchmark)
            local opts="$common_opts --all --cpu --memory --disk --network --quick --full --threads --size --iterations --output --json --compare"
            ;;
        config-manager)
            local opts="$common_opts --script get set delete list search edit reset import export profile interactive"
            ;;
        log-aggregator)
            local opts="$common_opts --source --file --remote --pattern --level --since --until --tail --lines --aggregate --stats --correlate --output --format --alert --alert-email"
            ;;
        metrics-reporter)
            local opts="$common_opts --type --metric --process --interval --duration --threshold --output --format --timestamp --labels --aggregate --percentiles"
            ;;
        trend-analyzer)
            local opts="$common_opts --file --column --delimiter --time-col --analyze --forecast --anomalies --threshold --moving-avg --growth --seasonality --correlation --chart --output --format"
            ;;
        dashboard-generator)
            local opts="$common_opts --config --type --widgets --layout --refresh --title --theme --output --data-source --no-color"
            ;;
        data-converter)
            local opts="$common_opts --input --output --from --to --delimiter --pretty --validate --transform --filter --batch --recursive"
            ;;
        etl-pipeline)
            local opts="$common_opts --config --source-type --source-path --dest-type --dest-path --transform --validate --dry-run --parallel"
            ;;
        data-validator)
            local opts="$common_opts --input --schema --format --strict --show-errors --output"
            ;;
        migration-assistant)
            local opts="$common_opts --source --destination --type --batch-size --dry-run --no-validate --no-backup --resume"
            ;;
        *)
            opts="$common_opts"
            ;;
    esac
    
    # Handle subcommands for config-manager
    if [[ "$script_name" == "config-manager" ]] && [[ $cword -gt 1 ]]; then
        case "${words[1]}" in
            profile)
                opts="save load list"
                ;;
            get|set|delete)
                # Complete configuration keys
                if [[ -f ~/.config/awesome-bash-scripts/config.conf ]]; then
                    opts=$(grep -v '^#' ~/.config/awesome-bash-scripts/config.conf | cut -d= -f1 | tr '\n' ' ')
                fi
                ;;
        esac
    fi
    
    # File/directory completion for certain options
    case "$prev" in
        --file|--log-file|--output|--config|--source|--destination|--directory|--import|--export|--ssh-key)
            _filedir
            return
            ;;
        --interface)
            # Complete network interfaces
            opts=$(ls /sys/class/net/ 2>/dev/null | tr '\n' ' ')
            ;;
        --service)
            # Complete systemd services
            opts=$(systemctl list-units --type=service --all --no-legend | awk '{print $1}' | sed 's/.service$//' | tr '\n' ' ')
            ;;
        --type)
            case "$script_name" in
                backup-manager)
                    opts="full incremental differential"
                    ;;
                database-backup)
                    opts="mysql postgresql mongodb sqlite"
                    ;;
                password-generator)
                    opts="random memorable pronounceable passphrase pin"
                    ;;
                metrics-reporter)
                    opts="system process network disk custom"
                    ;;
                dashboard-generator)
                    opts="terminal html both"
                    ;;
                migration-assistant)
                    opts="file directory csv-to-json"
                    ;;
            esac
            ;;
        --format)
            case "$script_name" in
                metrics-reporter)
                    opts="text json prometheus influx graphite csv"
                    ;;
                log-aggregator|trend-analyzer|data-converter|data-validator)
                    opts="text json csv xml yaml html"
                    ;;
                *)
                    opts="text json csv xml"
                    ;;
            esac
            ;;
        --from|--to)
            opts="json csv xml yaml toml"
            ;;
        --compression)
            opts="gzip bzip2 xz none"
            ;;
        --algorithm)
            opts="md5 sha256"
            ;;
    esac
    
    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
    return 0
}

# Generate completions for all abs- prefixed scripts
_abs_generate_completions() {
    # Find all scripts in the scripts directory
    local scripts_dir="${ABS_BASE_DIR:-/usr/local/share/awesome-bash-scripts}/scripts"
    
    if [[ ! -d "$scripts_dir" ]]; then
        scripts_dir="$HOME/.local/share/awesome-bash-scripts/scripts"
    fi
    
    if [[ -d "$scripts_dir" ]]; then
        # Register completion for each script
        for script in $(find "$scripts_dir" -name "*.sh" -type f); do
            local script_name=$(basename "$script" .sh)
            complete -F _abs_complete "abs-${script_name}"
        done
    fi
    
    # Also register for scripts that might be in PATH
    for cmd in abs-system-monitor abs-service-monitor abs-log-analyzer abs-network-monitor \
               abs-backup-manager abs-database-backup abs-sync-backup \
               abs-file-organizer abs-duplicate-finder abs-bulk-renamer \
               abs-system-info abs-package-cleanup \
               abs-security-audit abs-firewall-manager \
               abs-port-scanner abs-bandwidth-monitor \
               abs-password-generator abs-system-benchmark \
               abs-config-manager; do
        complete -F _abs_complete "$cmd"
    done
}

# Main awesome-bash command completion
_awesome_bash_complete() {
    local cur prev words cword
    _init_completion || return
    
    if [[ $cword -eq 1 ]]; then
        # Complete with available scripts
        local scripts=$(find ~/.local/share/awesome-bash-scripts/scripts -name "*.sh" -type f 2>/dev/null | xargs -n1 basename -s .sh | tr '\n' ' ')
        COMPREPLY=($(compgen -W "$scripts --help --version --list" -- "$cur"))
    else
        # Delegate to script-specific completion
        _abs_complete
    fi
    
    return 0
}

# Register completions
complete -F _awesome_bash_complete awesome-bash
_abs_generate_completions

# Also provide completion for the main install script
complete -F _longopt install.sh

# Completion for test-runner
_test_runner_complete() {
    local cur prev words cword
    _init_completion || return
    
    local opts="--help --verbose --quiet --unit --integration --performance --coverage --filter --no-color"
    
    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
    return 0
}

complete -F _test_runner_complete test-runner.sh

# Helper function to reload completions
reload_abs_completions() {
    _abs_generate_completions
    echo "Awesome Bash Scripts completions reloaded"
}

# Export functions
export -f _abs_complete
export -f _awesome_bash_complete
export -f reload_abs_completions
