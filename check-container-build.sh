#!/bin/bash

# It requires the hash to access the RPMS to be stored in the s3-hash.txt file.

REPO_URL="${REPO_URL-"https://github.com/freeipa/freeipa-openshift-container.git"}"
BASE_URL="http://freeipa-org-pr-ci.s3-website.eu-central-1.amazonaws.com/jobs"
S3_HASH="${S3_HASH-"$( cat s3-hash.txt )"}"
URL="${BASE_URL}/${S3_HASH}/rpms"

TARGET_DIR="tmp"

[ -e "${TARGET_DIR}" ] || mkdir -p "${TARGET_DIR}"


function yield
{
    echo "$*" >&2
} # yield

function error-msg
{
    yield "ERROR:$*"
} # error-msg

function die
{
    local err=$?
    [ $err -eq 0 ] && err=127
    error-msg "${FUNCNAME[1]}:$*"
    exit $err
} # die

# Copy URL contents to /etc/yum.repos.d/ in the container
function download-artifacts
{
    local basepath
    basepath="$1"
    curl --silent "${URL}/${basepath}" \
    | xsltproc --html prci-artifacts-list.xslt - \
    | tail -n +2 \
    | while read -r file
    do
        path="${file##${URL}/}"
        [ "$path" == "" ] && continue
        [ "$path" == "../" ] && continue
        if [ "${path%/}" != "${path}" ]
        then
            mkdir -p "${TARGET_DIR}/${basepath}${path}"
            download-artifacts "${basepath}${path}"
            continue
        fi
        curl --silent --output "${TARGET_DIR}/${basepath}${path}" "${URL}/${basepath}${path}"
    done
} # download-artifacts


function generate-repo-file
{
    local input
    local output
    input="$1"
    output="$2"

    [ -e "$input" ] || die "'${input}' file does not exist"
    envsubst <"${input}" >"${output}"
} # generate-repo-file


function is-patched-dockerfile
{
    local dockerfilepath
    dockerfilepath="$1"
    grep -q "/etc/yum.repos.d/freeipa-development.repo" "${dockerfilepath}"
} # is-patched-dockerfile


function patch-dockerfile
{
    local dockerfilepath
    local repofilepath

    dockerfilepath="$1"
    repofilepath="$2"
    [ -e "${repofilepath}" ] || die "'${repofilepath}' .repo file can not be found."
    [ -e "${dockerfilepath}" ] || die "'${dockerfilepath}' Dockerfile file can not be found."

    is-patched-dockerfile "${dockerfilepath}" && return 0 # Nothing to do

    mapfile -t lines < "${dockerfilepath}"
    > "${dockerfilepath}"
    for line in "${lines[@]}"
    do
        if [[ "${line}" =~ ^FROM\ * ]]
        then
            printf "%s\n" "${line}" >> "${dockerfilepath}"
            printf "COPY \"%s\" \"%s\"" "$( basename "${repofilepath}" )" "/etc/yum.repos.d/freeipa-development.repo" >> "${dockerfilepath}"
        else
            printf "%s\n" "${line}" >> "${dockerfilepath}"
        fi
    done
} # patch-dockerfile


function clone-repository
{
    local repo_url
    repo_url="$1"
    
    [ -e "repo" ] || git clone --depth 1 -b master "${repo_url}" repo
} # clone-repository


# download-artifacts ""
clone-repository "${REPO_URL}"
S3_HASH="${S3_HASH}" generate-repo-file freeipa-prci.repo.envsubst repo/freeipa-prci.repo

successed_files=()
failured_files=()
for item in repo/Dockerfile.*
do
    system="${item##*.}"
    case "${system}" in
        "fedora-32" \
        | "fedora-31" \
        | "fedora-23" \
        | "centos-7" \
        | "centos-8" )
            yield "INFO:Checking ${item}"
            ;;
        * )
            yield "INFO:Ignoring ${item}"
            continue
            ;;
    esac
    cp -f "${item}" "Dockerfile"
    [ -e logs ] || mkdir logs
    log_file="logs/$( basename "${item}" ).log"
    patch-dockerfile Dockerfile repo/freeipa-prci.repo
    set -o pipefail
    if sudo docker build --security-opt unconfined -f Dockerfile repo 2>&1 | tee "${log_file}" >/dev/null
    then
        yield "INFO:$( basename "${item}" ) build properly"
        successed_files+=( "$( basename "${item}" )")
    else
        yield "ERROR:$( basename "${item}" ) failed to build"
        tail "${log_file}" >&2
        failured_files+=( "$( basename "${item}" )")
    fi
done

# Files build successfully
echo ">> Successed files"
for item in "${successed_files[@]}"
do
    echo "${item}"
done

# Files which failed
echo ">> Failed files"
for item in "${failured_files[@]}"
do
    echo ">>> ${item}"
    tail logs/${item}.log
done
