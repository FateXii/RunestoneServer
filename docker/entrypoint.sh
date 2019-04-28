#!/bin/bash

# Fail early upon error
set -eu

info () {
    echo "I: $@"
}

# This file will exist if we've initialized postgres
stamp=/var/lib/postgresql/9.6/main/initialized.stamp

# Ensure the user starting the container has provided a password
if [ -z "$POSTGRES_PASSWORD" ]
then
    echo "Please export \${POSTGRES_PASSWORD}"
    exit 1
fi

export WEB2PY_CONFIG=production
export WEB2PY_MIGRATE=Yes
export DBURL=postgresql://runestone:${POSTGRES_PASSWORD}@db/runestone

# Initialize the database
if [ ! -f "$stamp" ]; then
    info "Initializing"
    rsmanage initdb --
    
    # Setup students, if the file exists
    if [ -e '/srv/configs/instructors.csv' ]; then
        info "Setting up instructors"
        rsmanage inituser --fromfile /srv/configs/instructors.csv
        cut -d, -f1,6 /srv/configs/instructors.csv \
        | tr ',' ' ' \
        | while read n c ; do
            rsmanage addinstructor  --username $n --course $c
        done
    fi

    # Setup students, again if the file exists
    if [ -e '/srv/configs/students.csv' ]; then
        info "Setting up students"
        rsmanage inituser --fromfile /srv/configs/students.csv
        info "Students were provided -- disabling signup!"
        # Disable signup
        echo -e "\nauth.settings.actions_disabled.append('register')" >> $WEB2PY_PATH/applications/runestone/models/db.py
    fi

    touch "${stamp}"
else
    info "Already initialized"
fi

## Go through all books and build
info "Building & Deploying books"
cd "${BOOKS_PATH}"
/bin/ls | while read book; do
    (
        cd $book;
        runestone build && runestone deploy
    );
done

# Uncomment for debugging
# /bin/bash

# Run the beast
info "Starting the server"
cd "$WEB2PY_PATH"
python web2py.py --ip=0.0.0.0 --port=8080 --password="${POSTGRES_PASSWORD}" -K runestone --nogui -X runestone  &
sleep 3
info "Starting the scheduler"
python ${WEB2PY_PATH}/run_scheduler.py runestone
