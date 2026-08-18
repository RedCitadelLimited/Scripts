#!/usr/bin/env bash

#
# Rate-limit / client-IP header testing helper
#
# Usage:
#
#   ./rate_test.sh POST https://portal.example.test/account/recovery/request
#
# Required files:
#
#   request.txt
#   headers.txt
#   formats.txt
#
# request.txt is the source of truth for the HTTP request.
#
# The METHOD and URL supplied on the command line do NOT modify request.txt.
# They are used to verify that the supplied command matches the request
# contained in request.txt.
#
# Every generated request is stored in:
#
#   requests/
#
# Every complete response is stored in:
#
#   responses/
#
# Summary results are written to:
#
#   results.csv
#

set -u


#
# ------------------------------------------------------------
# Colours
# ------------------------------------------------------------
#

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
LIGHT_BLUE='\033[0;94m'
NC='\033[0m'


#
# ------------------------------------------------------------
# Files and folders
# ------------------------------------------------------------
#

REQUEST_FILE='request.txt'
HEADERS_FILE='headers.txt'
FORMATS_FILE='formats.txt'

REQUESTS_DIR='requests'
RESPONSES_DIR='responses'

OUT='results.csv'


#
# ------------------------------------------------------------
# Usage
# ------------------------------------------------------------
#

usage() {

    echo "Usage:"
    echo "  $0 METHOD https://host/path"
    echo
    echo "Example:"
    echo "  $0 POST https://portal.example.test/account/recovery/request"

}


#
# ------------------------------------------------------------
# Command-line validation
# ------------------------------------------------------------
#

if [ "$#" -ne 2 ]; then

    usage

    exit 1

fi


METHOD="$1"
TARGET="$2"


#
# HTTP method must be uppercase.
#

if [[ ! "$METHOD" =~ ^[A-Z]+$ ]]; then

    printf "${RED}Error: HTTP method must be uppercase.${NC}\n"

    echo
    echo "Example:"
    echo "  POST"

    exit 1

fi


#
# Require a complete HTTP or HTTPS URL.
#

if [[ ! "$TARGET" =~ ^https?:// ]]; then

    printf "${RED}Error: target must be a complete http:// or https:// URL.${NC}\n"

    echo
    echo "Example:"
    echo "  https://portal.example.test/account/recovery/request"

    exit 1

fi


#
# ------------------------------------------------------------
# Required files
# ------------------------------------------------------------
#

for file in \
    "$REQUEST_FILE" \
    "$HEADERS_FILE" \
    "$FORMATS_FILE"
do

    if [ ! -f "$file" ]; then

        printf "${RED}Error: %s not found.${NC}\n" "$file"

        exit 1

    fi

done


#
# ------------------------------------------------------------
# Output folders
# ------------------------------------------------------------
#

mkdir -p "$REQUESTS_DIR"
mkdir -p "$RESPONSES_DIR"


#
# ------------------------------------------------------------
# Parse request.txt request line
# ------------------------------------------------------------
#
# Example request.txt:
#
#   POST /account/recovery/request HTTP/2
#   Host: portal.example.test
#   Content-Type: application/json
#
#   {"example":"value"}
#

request_line=$(
    head -n 1 "$REQUEST_FILE" |
    tr -d '\r'
)


REQUEST_METHOD=$(
    printf '%s\n' "$request_line" |
    awk '{print $1}'
)


REQUEST_PATH=$(
    printf '%s\n' "$request_line" |
    awk '{print $2}'
)


REQUEST_VERSION=$(
    printf '%s\n' "$request_line" |
    awk '{print $3}'
)


#
# Basic validation of request line.
#

if [ -z "$REQUEST_METHOD" ] || \
   [ -z "$REQUEST_PATH" ] || \
   [ -z "$REQUEST_VERSION" ]; then

    printf "${RED}Error: invalid first line in request.txt.${NC}\n"

    echo
    echo "Expected something similar to:"
    echo
    echo "  POST /account/recovery/request HTTP/2"

    exit 1

fi


#
# ------------------------------------------------------------
# Extract Host header
# ------------------------------------------------------------
#

REQUEST_HOST=$(
    grep -i '^Host:' "$REQUEST_FILE" |
    head -n 1 |
    cut -d':' -f2- |
    tr -d '\r' |
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
)


if [ -z "$REQUEST_HOST" ]; then

    printf "${RED}Error: request.txt does not contain a Host header.${NC}\n"

    exit 1

fi


#
# ------------------------------------------------------------
# Parse command-line target
# ------------------------------------------------------------
#

target_without_scheme="${TARGET#*://}"

TARGET_HOST="${target_without_scheme%%/*}"


if [[ "$target_without_scheme" == */* ]]; then

    TARGET_PATH="/${target_without_scheme#*/}"

else

    TARGET_PATH="/"

fi


#
# ------------------------------------------------------------
# Verify command line matches request.txt
# ------------------------------------------------------------
#

if [ "$REQUEST_METHOD" != "$METHOD" ]; then

    printf "${RED}ERROR: HTTP method does not match request.txt.${NC}\n"

    echo
    echo "Command line : $METHOD"
    echo "request.txt  : $REQUEST_METHOD"

    exit 1

fi


if [ "$REQUEST_HOST" != "$TARGET_HOST" ]; then

    printf "${RED}ERROR: Host does not match request.txt.${NC}\n"

    echo
    echo "Command line : $TARGET_HOST"
    echo "request.txt  : $REQUEST_HOST"

    exit 1

fi


if [ "$REQUEST_PATH" != "$TARGET_PATH" ]; then

    printf "${RED}ERROR: Endpoint does not match request.txt.${NC}\n"

    echo
    echo "Command line : $TARGET_PATH"
    echo "request.txt  : $REQUEST_PATH"

    exit 1

fi


#
# ------------------------------------------------------------
# Extract request body
# ------------------------------------------------------------
#

blank_line=$(
    awk '
        {
            gsub(/\r$/, "")
        }

        /^$/ {
            print NR
            exit
        }
    ' "$REQUEST_FILE"
)


REQUEST_BODY=''


if [ -n "$blank_line" ]; then

    REQUEST_BODY=$(
        tail -n +"$((blank_line + 1))" "$REQUEST_FILE" |
        sed 's/\r$//'
    )

fi


#
# ------------------------------------------------------------
# Extract headers from request.txt
# ------------------------------------------------------------
#
# The following are deliberately omitted:
#
#   Host
#   Content-Length
#
# curl derives Host from the supplied URL and calculates Content-Length
# from the body.
#

declare -a BASE_HEADERS=()


while IFS= read -r line || [ -n "$line" ]; do

    line="${line%$'\r'}"


    #
    # Blank line marks the start of the body.
    #

    [ -z "$line" ] && break


    #
    # Skip the HTTP request line.
    #

    if [[ "$line" =~ ^[A-Z]+[[:space:]] ]]; then
        continue
    fi


    #
    # Skip Host.
    #

    if [[ "$line" =~ ^[Hh][Oo][Ss][Tt]: ]]; then
        continue
    fi


    #
    # Skip Content-Length.
    #

    if [[ "$line" =~ ^[Cc][Oo][Nn][Tt][Ee][Nn][Tt]-[Ll][Ee][Nn][Gg][Tt][Hh]: ]]; then
        continue
    fi


    BASE_HEADERS+=(
        --header "$line"
    )


done < "$REQUEST_FILE"


#
# ------------------------------------------------------------
# Count headers and formats
# ------------------------------------------------------------
#

header_count=$(
    grep -cv '^[[:space:]]*$' "$HEADERS_FILE"
)


format_count=$(
    grep -cv '^[[:space:]]*$' "$FORMATS_FILE"
)


total_requests=$((header_count * format_count))


#
# ------------------------------------------------------------
# Pre-run information
# ------------------------------------------------------------
#

printf '\n'

printf "${CYAN}Request validation${NC}\n"

printf 'Method        : %s\n' "$METHOD"
printf 'Target        : %s\n' "$TARGET"
printf 'Request file  : %s\n' "$REQUEST_FILE"
printf 'HTTP version  : %s\n' "$REQUEST_VERSION"
printf 'Host          : %s\n' "$REQUEST_HOST"
printf 'Endpoint      : %s\n' "$REQUEST_PATH"

printf '\n'

printf 'Headers       : %s\n' "$header_count"
printf 'Formats       : %s\n' "$format_count"
printf 'Requests      : %s\n' "$total_requests"


#
# ------------------------------------------------------------
# Confirmation for large test sets
# ------------------------------------------------------------
#

if [ "$total_requests" -gt 100 ]; then

    printf '\n'

    printf "${YELLOW}WARNING: This test will send %s requests.${NC}\n" \
        "$total_requests"

    read -r -p "Do you want to continue? [y/N] " confirm


    case "$confirm" in

        y|Y|yes|YES)

            ;;

        *)

            echo "Cancelled."

            exit 0

            ;;

    esac

fi


printf '\n'


#
# ------------------------------------------------------------
# CSV output
# ------------------------------------------------------------
#

printf '"request","method","target","header","format","status","remaining","reset","time","redirect","error","request_file","response_file"\n' \
    > "$OUT"


#
# ------------------------------------------------------------
# Console table
# ------------------------------------------------------------
#

printf "${CYAN}%-6s | %-7s | %-32s | %-45s | %-6s | %-9s | %-7s | %-10s | %-45s${NC}\n" \
    "REQ" \
    "METHOD" \
    "HEADER" \
    "VALUE" \
    "STATUS" \
    "REMAINING" \
    "RESET" \
    "TIME" \
    "REDIRECT"


printf '%s\n' \
    "-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"


#
# ------------------------------------------------------------
# Request counter
# ------------------------------------------------------------
#

request_no=0


#
# ------------------------------------------------------------
# Main test loop
# ------------------------------------------------------------
#

while IFS= read -r header || [ -n "$header" ]; do

    header="${header%$'\r'}"

    [ -z "$header" ] && continue


    while IFS= read -r value || [ -n "$value" ]; do

        value="${value%$'\r'}"

        [ -z "$value" ] && continue


        #
        # Increment request number.
        #

        request_no=$((request_no + 1))


        #
        # headers.txt:
        #
        #   X-Forwarded-For:
        #
        # formats.txt:
        #
        #   127.0.0.1
        #
        # Becomes:
        #
        #   X-Forwarded-For: 127.0.0.1
        #

        injected_header="$header $value"


        #
        # Capture file names.
        #

        request_file=$(printf \
            '%s/request_%05d.txt' \
            "$REQUESTS_DIR" \
            "$request_no"
        )


        response_file=$(printf \
            '%s/response_%05d.txt' \
            "$RESPONSES_DIR" \
            "$request_no"
        )


        response_headers=$(mktemp)
        response_body=$(mktemp)


        #
        # ------------------------------------------------------------
        # Save generated request
        # ------------------------------------------------------------
        #
        # The injected header is inserted immediately before the blank
        # line separating the headers and body.
        #

        awk \
            -v inject="$injected_header" '
            BEGIN {
                inserted = 0
            }

            {
                sub(/\r$/, "")
            }

            /^$/ && !inserted {

                print inject

                inserted = 1

                print ""

                next
            }

            {
                print
            }

            END {

                if (!inserted) {

                    print inject

                    print ""

                }

            }
        ' "$REQUEST_FILE" > "$request_file"


        #
        # ------------------------------------------------------------
        # Build curl request
        # ------------------------------------------------------------
        #

        curl_args=(

            -sk

            --http2

            --connect-timeout 5

            --max-time 15

            --request "$METHOD"

            "${BASE_HEADERS[@]}"

            --header "$injected_header"

            --dump-header "$response_headers"

            --output "$response_body"

            --write-out '%{http_code}|%{time_total}|%{errormsg}'

        )


        #
        # Preserve the body from request.txt.
        #

        if [ -n "$REQUEST_BODY" ]; then

            curl_args+=(

                --data-binary "$REQUEST_BODY"

            )

        fi


        curl_args+=(

            "$TARGET"

        )


        #
        # ------------------------------------------------------------
        # Send request
        # ------------------------------------------------------------
        #

        result=$(
            curl "${curl_args[@]}"
        )


        #
        # ------------------------------------------------------------
        # Parse curl result
        # ------------------------------------------------------------
        #

        status=$(
            printf '%s' "$result" |
            cut -d'|' -f1
        )


        timing=$(
            printf '%s' "$result" |
            cut -d'|' -f2
        )


        error=$(
            printf '%s' "$result" |
            cut -d'|' -f3-
        )


        #
        # ------------------------------------------------------------
        # Rate-limit remaining
        # ------------------------------------------------------------
        #
        # First look for the standard/general form:
        #
        #   X-RateLimit-Remaining: 2
        #
        # If absent, accept a suffixed variant:
        #
        #   X-RateLimit-Remaining-Something: 2
        #
        # This avoids hard-coding an application-specific suffix.
        #

        remaining=$(
            grep -i '^X-Ratelimit-Remaining:' "$response_headers" \
            |
            tail -1 \
            |
            cut -d':' -f2- \
            |
            tr -d '\r' \
            |
            xargs
        )


        if [ -z "$remaining" ]; then

            remaining=$(
                grep -Ei '^X-Ratelimit-Remaining-[^:]+:' "$response_headers" \
                |
                tail -1 \
                |
                cut -d':' -f2- \
                |
                tr -d '\r' \
                |
                xargs
            )

        fi


        [ -z "$remaining" ] && remaining="-"


        #
        # ------------------------------------------------------------
        # Rate-limit reset
        # ------------------------------------------------------------
        #
        # Checks, in order:
        #
        #   X-RateLimit-Reset:
        #
        #   X-RateLimit-Reset-<suffix>:
        #
        #   Retry-After:
        #
        # Retry-After is commonly expressed as a number of seconds.
        #

        reset=$(
            grep -i '^X-Ratelimit-Reset:' "$response_headers" \
            |
            tail -1 \
            |
            cut -d':' -f2- \
            |
            tr -d '\r' \
            |
            xargs
        )


        if [ -z "$reset" ]; then

            reset=$(
                grep -Ei '^X-Ratelimit-Reset-[^:]+:' "$response_headers" \
                |
                tail -1 \
                |
                cut -d':' -f2- \
                |
                tr -d '\r' \
                |
                xargs
            )

        fi


        if [ -z "$reset" ]; then

            reset=$(
                grep -i '^Retry-After:' "$response_headers" \
                |
                tail -1 \
                |
                cut -d':' -f2- \
                |
                tr -d '\r' \
                |
                xargs
            )

        fi


        [ -z "$reset" ] && reset="-"


        #
        # ------------------------------------------------------------
        # Redirect
        # ------------------------------------------------------------
        #
        # Reads the Location response header.
        #
        # Examples:
        #
        #   Location: /signin
        #
        #   Location: https://portal.example.test/signin
        #

        redirect=$(
            grep -i '^Location:' "$response_headers" \
            |
            tail -1 \
            |
            cut -d':' -f2- \
            |
            tr -d '\r' \
            |
            xargs
        )


        [ -z "$redirect" ] && redirect="-"


        #
        # ------------------------------------------------------------
        # Save complete response
        # ------------------------------------------------------------
        #

        {
            cat "$response_headers"

            printf '\n'

            cat "$response_body"

        } > "$response_file"


        #
        # ------------------------------------------------------------
        # Response colour
        # ------------------------------------------------------------
        #

        case "$status" in

            204)

                row_colour="$GREEN"

                ;;

            429)

                row_colour="$RED"

                ;;

            000)

                row_colour="$YELLOW"

                ;;

            *)

                row_colour="$NC"

                ;;

        esac


        #
        # ------------------------------------------------------------
        # Console output
        # ------------------------------------------------------------
        #

        printf "${row_colour}%-6s | %-7s | %-32s | %-45s | %-6s | %-9s | %-7s | %-10s |${NC} " \
            "$request_no" \
            "$METHOD" \
            "$header" \
            "$value" \
            "$status" \
            "$remaining" \
            "$reset" \
            "$timing"


        #
        # Redirect is deliberately the final column.
        #
        # Only the redirect value itself is light blue.
        #

        if [ "$redirect" != "-" ]; then

            printf "${LIGHT_BLUE}%-45s${NC}" "$redirect"

        else

            printf "${row_colour}%-45s${NC}" "-"

        fi


        #
        # Display curl errors after the table for status 000.
        #

        if [ "$status" = "000" ] && [ -n "$error" ]; then

            printf " | ${YELLOW}%s${NC}" "$error"

        fi


        printf '\n'


        #
        # ------------------------------------------------------------
        # CSV escaping
        # ------------------------------------------------------------
        #

        csv_method=${METHOD//\"/\"\"}
        csv_target=${TARGET//\"/\"\"}
        csv_header=${header//\"/\"\"}
        csv_value=${value//\"/\"\"}
        csv_error=${error//\"/\"\"}
        csv_redirect=${redirect//\"/\"\"}
        csv_request_file=${request_file//\"/\"\"}
        csv_response_file=${response_file//\"/\"\"}


        #
        # ------------------------------------------------------------
        # CSV row
        # ------------------------------------------------------------
        #

        printf '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"\n' \
            "$request_no" \
            "$csv_method" \
            "$csv_target" \
            "$csv_header" \
            "$csv_value" \
            "$status" \
            "$remaining" \
            "$reset" \
            "$timing" \
            "$csv_redirect" \
            "$csv_error" \
            "$csv_request_file" \
            "$csv_response_file" \
            >> "$OUT"


        #
        # Temporary files no longer required.
        #

        rm -f \
            "$response_headers" \
            "$response_body"


    done < "$FORMATS_FILE"


done < "$HEADERS_FILE"


#
# ------------------------------------------------------------
# Complete
# ------------------------------------------------------------
#

printf '\n'

printf '[+] Completed %s requests.\n' "$request_no"

printf '[+] Results          : %s\n' "$OUT"

printf '[+] Request captures : %s/\n' "$REQUESTS_DIR"

printf '[+] Response captures: %s/\n' "$RESPONSES_DIR"
