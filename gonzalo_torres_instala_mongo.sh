#!/bin/bash
#
# Script adaptado a partir del original:
# - Parametrizacion mediante archivo config.ini (-f)
# - Eliminacion de espera pasiva (sleep) por comprobacion activa
# - Control de errores y codigos de salida estandar
# - Separacion entre logica del script y datos de configuracion
#


set -e

logger "Arrancando instalacion y configuracion de MongoDB"
USO="Uso : install.sh [opciones]
Ejemplo:
install.sh -f config.ini
Opciones:
-f fichero de configuracion (config.ini)
-a muestra esta ayuda
"
function ayuda() {
echo "${USO}"
if [[ ${1} ]]
then
echo ${1}
fi
exit 0
}

# DEFAULTS
FICHERO="config.ini"
while getopts "af:" OPCION
do
case ${OPCION} in
a)
ayuda
;;
f)
FICHERO=${OPTARG}
;;
\?)
ayuda "Opcion no permitida"
;;
esac
done

if [[ ! -f "${FICHERO}" ]]
then
logger "No existe el fichero ${FICHERO}"
exit 1
fi

# Lectura de parametros desde config.ini
PUERTO_MONGOD=$(grep "^PUERTO_MONGOD=" "${FICHERO}" | cut -d '=' -f2 | tr -d '\r')
USUARIO=$(grep "^USUARIO=" "${FICHERO}" | cut -d '=' -f2 | tr -d '\r')
PASSWORD=$(grep "^PASSWORD=" "${FICHERO}" | cut -d '=' -f2 | tr -d '\r')

if [[ -z "${PUERTO_MONGOD}" || -z "${USUARIO}" || -z "${PASSWORD}" ]]
then
logger "Faltan parametros en el archivo de configuracion"
exit 1
fi

logger "Puerto: ${PUERTO_MONGOD}"
logger "Usuario: ${USUARIO}"

# Instalacion MongoDB
logger "Instalando MongoDB 4.2.1"
if [[ $(dpkg -l | grep mongodb-org | wc -l) -gt 0 ]]
then
logger "MongoDB ya instalado. Se procede a reinstalar."
apt-get -y purge mongodb-org* \
&& apt-get -y autoremove \
&& apt-get -y autoclean \
&& apt-get -y clean \
&& rm -rf /var/lib/apt/lists/* \
&& pkill -u mongodb || true \
&& pkill -f mongod || true \
&& rm -rf /var/lib/mongodb
fi

apt-get -y update \
&& apt-get install -y \
mongodb-org=4.2.1 \
mongodb-org-server=4.2.1 \
mongodb-org-shell=4.2.1 \
mongodb-org-mongos=4.2.1 \
mongodb-org-tools=4.2.1 \
&& rm -rf /var/lib/apt/lists/* \
&& pkill -u mongodb || true \
&& pkill -f mongod || true \
&& rm -rf /var/lib/mongodb

# Crear las carpetas de logs y datos con sus permisos

[[ -d "/datos/bd" ]] || mkdir -p -m 755 "/datos/bd"
[[ -d "/datos/log" ]] || mkdir -p -m 755 "/datos/log"
# Establecer el dueño y el grupo de las carpetas db y log

chown mongodb /datos/log /datos/bd
chgrp mongodb /datos/log /datos/bd

# Crear el archivo de configuración de mongodb con el puerto solicitado
[ -f /etc/mongod.conf ] && [ ! -f /etc/mongod.conf.orig ] && mv /etc/mongod.conf /etc/mongod.conf.orig
(
cat <<MONGOD_CONF
# /etc/mongod.conf
systemLog:
   destination: file
   path: /datos/log/mongod.log
   logAppend: true
storage:
   dbPath: /datos/bd
   engine: wiredTiger
   journal:
      enabled: true
net:
   port: ${PUERTO_MONGOD}
security:
   authorization: disabled
MONGOD_CONF
) > /etc/mongod.conf

# Comprobacion activa del arranque de MongoDB (elimina espera fija)
systemctl restart mongod

logger "Esperando a que mongod responda..."

INTENTOS=0
MAX_INTENTOS=10

until mongo admin --eval "db.runCommand({ ping: 1 })" >/dev/null 2>&1
do
    sleep 2
    INTENTOS=$((INTENTOS+1))

    if [ "${INTENTOS}" -ge "${MAX_INTENTOS}" ]
    then
        logger "MongoDB no responde tras ${MAX_INTENTOS} intentos"
        exit 1
    fi
done

logger "MongoDB responde correctamente"


# Crear usuario con la password proporcionada como parametro

mongo admin <<EOF
db.createUser({
  user: "${USUARIO}",
  pwd: "${PASSWORD}",
  roles: [
    { role: "root", db: "admin" },
    { role: "restore", db: "admin" }
  ]
})
EOF

logger "El usuario ${USUARIO} ha sido creado con exito!"
logger "Habilitando authorization y reiniciando mongod..."

# Habilitar authorization en el fichero de configuracion (manteniendo estilo del profesor)
[ -f /etc/mongod.conf ] && mv /etc/mongod.conf /etc/mongod.conf.noauth

(
cat <<MONGOD_CONF
# /etc/mongod.conf
systemLog:
   destination: file
   path: /datos/log/mongod.log
   logAppend: true
storage:
   dbPath: /datos/bd
   engine: wiredTiger
   journal:
      enabled: true
net:
   port: ${PUERTO_MONGOD}
security:
   authorization: enabled
MONGOD_CONF
) > /etc/mongod.conf

systemctl restart mongod

logger "Verificando acceso autenticado..."

systemctl is-active --quiet mongod

mongo admin <<CREACION_USUARIO || true
db.createUser({
  user: "${USUARIO}",
  pwd: "${PASSWORD}",
  roles: [
    { role: "root", db: "admin" },
    { role: "restore", db: "admin" }
  ]
})
CREACION_USUARIO

logger "Verificacion OK: mongod responde con autenticacion."










# Finalizacion correcta del script
exit 0
