#!/bin/bash

DOMAIN=$1
VAULT_TOKEN=$2
VAULT_ADDR=$3
CSR_FILE="${DOMAIN}.csr"
CERT_FILE="${DOMAIN}.crt"
ROLE_NAME=$4
KV_PATH="kv"

# генерация приватного ключа и CSR файла
openssl genpkey -algorithm RSA -out "${DOMAIN}.key" -pkeyopt rsa_keygen_bits:2048
openssl req -new -key "${DOMAIN}.key" -out ${CSR_FILE} -subj "/CN=${DOMAIN}"

# проверка, что CSR файл создан
if [ ! -f "${CSR_FILE}" ]; then
    echo "ошибка: файл CSR не создан."
    exit 1
fi

# чтение CSR файла
CSR_CONTENT=$(cat ${CSR_FILE})

# проверка содержимого CSR файла
if [ -z "${CSR_CONTENT}" ]; then
    echo "ошибка: CSR файл пустой."
    exit 1
fi

# вывод содержимого CSR файла для отладки
echo "CSR содержимое: ${CSR_CONTENT}"

# создание JSON файла с использованием jq
JSON_DATA=$(jq -n --arg csr "${CSR_CONTENT}" --arg common_name "${DOMAIN}" '{csr: $csr, common_name: $common_name}')

# вывод JSON данных для отладки
echo "JSON data: ${JSON_DATA}"

# отправка CSR файла в Vault для генерации сертификата
RESPONSE=$(curl --silent --header "X-Vault-Token: ${VAULT_TOKEN}" --header "Content-Type: application/json" --request POST --data "${JSON_DATA}" ${VAULT_ADDR}/v1/pki/sign/${ROLE_NAME})

# вывод ответа для отладки
echo "Response from Vault: ${RESPONSE}"

# извлечение сертификата из ответа
CERTIFICATE=$(echo ${RESPONSE} | jq -r '.data.certificate')

# проверка, что сертификат не пустой
if [ "${CERTIFICATE}" == "null" ] || [ -z "${CERTIFICATE}" ]; then
    echo "ошибка: не удалось получить сертификат. ответ от Vault: ${RESPONSE}"
    exit 1
fi

# сохранение сертификата в файл
echo "${CERTIFICATE}" > ${CERT_FILE}

echo "Сертификат сохранен в ${CERT_FILE}"

# чтение приватного ключа
PRIVATE_KEY_CONTENT=$(cat "${DOMAIN}.key")

# проверка содержимого приватного ключа
if [ -z "${PRIVATE_KEY_CONTENT}" ]; then
    echo "ошибка: приватный ключ пустой."
    exit 1
fi

# создание JSON файла для приватного ключа
KEY_JSON_DATA=$(jq -n --arg key "${PRIVATE_KEY_CONTENT}" '{data: {key: $key}}')

# отправка приватного ключа в Vault
KEY_RESPONSE=$(curl --silent --header "X-Vault-Token: ${VAULT_TOKEN}" --header "Content-Type: application/json" --request POST --data "${KEY_JSON_DATA}" ${VAULT_ADDR}/v1/${KV_PATH}/data/${DOMAIN}/key)

# вывод ответа для отладки
echo "Response from Vault (key storage): ${KEY_RESPONSE}"

# проверка успешного сохранения приватного ключа
if echo "${KEY_RESPONSE}" | jq -e '.errors' > /dev/null; then
    echo "ошибка: не удалось сохранить приватный ключ. ответ от Vault: ${KEY_RESPONSE}"
    exit 1
fi

echo "Приватный ключ сохранен в Vault по пути ${KV_PATH}/${DOMAIN}/key"
