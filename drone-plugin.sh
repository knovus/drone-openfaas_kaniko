#!/busybox/sh

set -euo pipefail

#Prepare parameters to be used
if [[ "${PLUGIN_YAML:-}" ]]; then
    OF_YAML="--yaml ${PLUGIN_YAML}"

elif [ -f stack.yml ]; then
    OF_STACK_YAML="stack.yml"
fi

if [[ "${PLUGIN_TLS_NO_VERIFY:-}" == "true" ]]; then
    OF_TLS_NO_VERIFY="--tls-no-verify"
    KA_OPTIONS="--skip-tls-verify=true"
fi

if [[ "${PLUGIN_USERNAME:-}" ]]; then
    OF_USERNAME="--username ${PLUGIN_USERNAME}"
fi

if [[ "${PLUGIN_TAG:-}" ]]; then
    OF_TAG="--tag=${PLUGIN_TAG}"
fi

if [[ "${PLUGIN_IMAGE_NAME:-}" && "${PLUGIN_REGISTRY:-}" ]]; then
    OF_IMAGE="--image=${PLUGIN_REGISTRY}/${PLUGIN_IMAGE_NAME}"
    if [[ "${PLUGIN_YAML:-}" || "${OF_STACK_YAML:-}"]]; then
        OF_IMAGE_NAME_FULL="${PLUGIN_REGISTRY}/${PLUGIN_IMAGE_NAME}"
        sed -ie 's/\([[:space:]]*image: *\).*/\1${OF_IMAGE_NAME_FULL}/1' ${PLUGIN_YAML:-}${OF_STACK_YAML:-}
    fi
fi

if [[ "${PLUGIN_FUNCTION_NAME:-}" ]]; then
    OF_FUNCTION_NAME="${PLUGIN_FUNCTION_NAME}"
else
    echo "ERROR: Must provide a OpenFaaS Functions Name (function_name parameter)"
    exit 1
fi

if [[ "${PLUGIN_URL:-}" ]]; then
    OF_URL="--gateway ${PLUGIN_URL}"
fi

#
#Executing commands!!!
#
#Pull store template if needed
echo "Fetching OpenFaaS Template..."
if [[ "${PLUGIN_TEMPLATE:-}" ]]; then
    /usr/local/bin/faas-cli template store pull "${PLUGIN_TEMPLATE}"
else
    /usr/local/bin/faas-cli template pull https://github.com/openfaas/templates.git
fi 

#Generate Step
echo "Generating Build Files..."
/usr/local/bin/faas-cli build ${OF_YAML:-} --shrinkwrap

#Build & Push Step
echo "Building a Publishing docker image with Kaniko..."
if [[ "${PLUGIN_REGISTRY_USERNAME:-}" && "${PLUGIN_REGISTRY_PASSWORD:-}" && "${PLUGIN_REGISTRY:-}" ]]; then
DOCKER_AUTH="{\"auths\":{\"${PLUGIN_REGISTRY}\":{\"username\":\"${PLUGIN_REGISTRY_USERNAME}\",\"password\":\"${PLUGIN_REGISTRY_PASSWORD}\"}}}"
cat ${DOCKER_AUTH} > /kaniko/.docker/config.json
/kaniko/executor -v info \
    --context=./build/${OF_FUNCTION_NAME} \
    --dockerfile=./build/${OF_FUNCTION_NAME}/Dockerfile \
    --destination=${OF_IMAGE_NAME_FULL} \
    ${KA_OPTIONS:-}
else
    echo "ERROR: Must provide a Docker Registry Username (registry_username or plugin_registry_username secret) and Password (registry_password or plugin_registry_password secret) parameters to Build and Pushish a Docker Image"
    exit 1
fi

#Deploy Step
if [[ -n "${PLUGIN_PASSWORD:-}" && -n "${PLUGIN_URL:-}" ]]; then
    #Login to OpenFaaS Gateway
    echo ${PLUGIN_PASSWORD} | /usr/local/bin/faas-cli login ${OF_USERNAME:-} --password-stdin ${OF_URL:-} ${TLS_NO_VERIFY:-}
    #Deploy the function
    /usr/local/bin/faas-cli deploy ${OF_YAML:-} ${OF_URL} ${OF_IMAGE:-} ${OF_TAG:-}
else
    echo "ERROR: Must provide a OpenFaaS Gateway URL (url or plugin_url secret) and Password (password or plugin_password secret) parameters to Deploy"
    exit 1
fi