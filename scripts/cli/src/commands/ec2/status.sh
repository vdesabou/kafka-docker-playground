instance_name="${args[--instance]}"
all="${args[--all]}"

for instance in $(ec2_instance_list)
do
    name=$(echo "${instance}" | cut -d "/" -f 1)
    state=$(echo "${instance}" | cut -d "/" -f 2)
    ip=$(echo "${instance}" | cut -d "/" -f 3)
    id=$(echo "${instance}" | cut -d "/" -f 4)

    if [ "$name" = "$instance_name" ]
    then
        if [[ -n "$all" ]]
        then
            echo "$name/$state/$ip/$id"
        else
            echo "$state"
        fi
    fi
done