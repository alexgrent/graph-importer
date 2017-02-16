#!/bin/bash

#-----------------------------------------------------------
# Script for an initial setup and dataimport import of Reactome to the Graph
# WARNING: do not execute as sudo, permission will be asked when required
#
# 4 March 2015
# Florian Korninger - fkorn@ebi.ac.uk
#  
#-----------------------------------------------------------

usage="
Script for an initial setup and dataimport import of Reactome to the Graph
WARNING: Do not execute as sudo, permission will be asked when required

The password will only be updated after installing or updating the neo4j server
The neo4j server can be updated without uninstalling it before.
WARNING: If no password is specified the old password will persist.

$(basename "$0") [-r <reactome_host> -s <reactome_port> —t <reactome_db_name> -u <reactome_db_user> -v <reactome_db_password> -d <neo4j_db_directory> -e <neo4j_db_name> -j <import_data> -i <install_neo4j> -m <neo4j_user> -n <neo4j_password> ]

where:
    -h  Program help/usage
    -r  Reactome database host. DEFAULT: localhost
    -s  Reactome database port. DEFAULT: 3306
    -t  Reactome database name. DEFAULT: reactome
    -u  Reactome database user. DEFAULT: reactome
    -v  Reactome database password. DEFAULT: reactome
    -d  Neo4j directory of Db. DEFAULT: /var/lib/neo4j/data/
    -e  Neo4j name of graph Db. DEFAULT: graph.db
    -j  Import Reactome data. DEFAULT: false
    -i  Install neo4j. DEFAULT: false
    -n  Neo4j password (only set when neo4j is installed)."	

_REACTOME_HOST="localhost"
_REACTOME_PORT=3306
_REACTOME_DATABASE="reactome"
_REACTOME_USER="reactome"
_REACTOME_PASSWORD="reactome"
_GRAPH_DIR="/var/lib/neo4j/data/databases/"
_GRAPH_NAME="graph.db"
_IMPORT_DATA=false
_INSTALL_NEO4J=false

_PROBLEMS=0

# :h (help) should be at the very end of the while loop
while getopts ":r:s:t:u:v:d:e:m:n:ijh" option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    r) _REACTOME_HOST=$OPTARG
       ;;
    s) _REACTOME_PORT=$OPTARG
       ;;
    t) _REACTOME_DATABASE=$OPTARG
       ;;
    u) _REACTOME_USER=$OPTARG
       ;;
    v) _REACTOME_PASSWORD=$OPTARG
       ;; 
    d) _GRAPH_DIR=$OPTARG
       ;;
    e) _GRAPH_NAME=$OPTARG
       ;;
    i) _INSTALL_NEO4J=true
       ;;
    j) _IMPORT_DATA=true
       ;;
    n) _NEO4J_PASSWORD=$OPTARG
       ;;
   \?) echo "Invalid option: -$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
  esac
done
shift $((OPTIND - 1))

if ${_INSTALL_NEO4J} = true; then
    echo "start installing neo4j"
    sudo sh -c "wget -O - https://debian.neo4j.org/neotechnology.gpg.key | sudo apt-key add -" >/dev/null 2>&1
    sudo sh -c "echo 'deb http://debian.neo4j.org/repo stable/' >/tmp/neo4j.list" >/dev/null 2>&1
    sudo mv /tmp/neo4j.list /etc/apt/sources.list.d
    sudo apt-get update
    sudo apt-get install neo4j
    echo "installing neo4j finished"
    if [ ! -z "$_NEO4J_PASSWORD" ]; then 
	echo "removing old authentication"
	if sudo service neo4j status >/dev/null 2>&1; then
            echo "Shutting down Neo4j DB"
            if ! sudo service neo4j stop >/dev/null 2>&1; then
            	echo "an error occurred while trying to shut down neo4j db"
		exit 1
    	    fi
	fi
	sudo rm /var/lib/neo4j/data/dbms/auth
	if ! sudo service neo4j status >/dev/null 2>&1; then
	    if ! sudo service neo4j start >/dev/null 2>&1; then
		echo "An error occurred while trying to start neo4j"
		exit 1
	    fi
	fi
	echo "setting new password for user neo4j"	
	curl -H "Content-Type: application/json" -X POST -d '{"password":"'${_NEO4J_PASSWORD}'"}' -u neo4j:neo4j http://localhost:7474/user/neo4j/password >/dev/null >/dev/null 2>&1
    fi 
fi

if ${_IMPORT_DATA} = true; then
    echo "Checking if current directory is valid project"
    if ! mvn -q clean package -DskipTests; then
        if [ ! -f /target/BatchImporter-jar-with-dependencies.jar ]; then
            echo "Cloning new repo from git"
            git clone https://github.com/reactome/graph-importer.git
            _PATH="/graph-importer"

            echo "Started packaging reactome project"
            if ! mvn -q -f .${_PATH}/pom.xml clean package -DskipTests; then
                echo "An error occurred when packaging the project"
                exit 1
            fi
        fi
    fi

    if [ "$_GRAPH_DIR" == "/var/lib/neo4j/data/" ]; then
        if sudo service neo4j status; then
            echo "Shutting down Neo4j DB in order to prepare dataimport import"
            if ! sudo service neo4j stop; then
                echo "An error occurred while trying to shut down neo4j db"
            exit 1
            fi
        fi
    fi

    if [ ! -d ${_GRAPH_DIR}${_GRAPH_NAME} ]; then
        echo "Creating new database folder"
        if ! sudo mkdir ${_GRAPH_DIR}${_GRAPH_NAME}; then
            echo "An error occurred while trying to create a new database folder"
            exit 1
        fi
    fi

    echo "Changing permissions of neo4j graph"
    if ! sudo chown -R ${USER} ${_GRAPH_DIR}${_GRAPH_NAME}; then
        echo "An error occurred when trying to change permissions of the neo4j graph"
    fi

    echo "Started importing data to the neo4j database"
    if ! java -jar .${_PATH}/target/BatchImporter-jar-with-dependencies.jar -h ${_REACTOME_HOST} -s ${_REACTOME_PORT} -d ${_REACTOME_DATABASE} -u ${_REACTOME_USER} -p ${_REACTOME_PASSWORD} -n ${_GRAPH_DIR}${_GRAPH_NAME}; then
        echo "An error occurred during the data import process"
        exit 1
    fi
    echo "DataImport finished successfully!"

    echo "Changing permissions of neo4j graph"
    if ! sudo chown -R neo4j ${_GRAPH_DIR}${_GRAPH_NAME}; then
        echo "An error occurred when trying to change permissions of the neo4j graph"
        exit 1
    fi
fi

if ! sudo service neo4j status >/dev/null 2>&1; then
    echo "Starting neo4j database"
    if ! sudo service neo4j start; then
        echo "Neo4j database could not be started"
        exit 1
    fi
fi

if [ ! -z "$_PATH" ]; then
    sudo rm -R graph-importer
fi
echo "Script finished with"  ${_PROBLEMS} "problems!"
