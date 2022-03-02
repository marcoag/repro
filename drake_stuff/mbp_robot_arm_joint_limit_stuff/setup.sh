#!/bin/bash

# Either source this, or use it as a prefix:
#
#   source ./setup.sh
#   ./my_program
#
# or
#
#   ./setup.sh ./my_program

_cur_dir=$(cd $(dirname ${BASH_SOURCE}) && pwd)
_venv_dir=${_cur_dir}/venv

_download_drake() { (
    # See: https://drake.mit.edu/from_binary.html
    # Download and echo path to stdout for capture.
    set -eux

    base=drake-20211111-focal.tar.gz
    dir=~/Downloads
    uri=https://drake-packages.csail.mit.edu/drake/nightly
    if [[ ! -f ${dir}/${base} ]]; then
        wget ${uri}/${base} -O ${dir}/${base}
    fi
    echo ${dir}/${base}
) }

_generate_sdf() { (

    echo '<sdf version="1.6">
    <world name="default">
        <plugin
        filename="ignition-gazebo-physics-system"
        name="ignition::gazebo::systems::Physics">
        </plugin>
        <plugin
        filename="ignition-gazebo-sensors-system"
        name="ignition::gazebo::systems::Sensors">
        <render_engine>ogre2</render_engine>
        <background_color>0, 1, 0</background_color>
        </plugin>
        <plugin
            filename="ignition-gazebo-user-commands-system"
            name="ignition::gazebo::systems::UserCommands">
        </plugin>
        <plugin
        filename="ignition-gazebo-scene-broadcaster-system"
        name="ignition::gazebo::systems::SceneBroadcaster">
        </plugin>
        <include>
        <uri>'$1'</uri>
        <plugin
            filename="ignition-gazebo-model-photo-shoot-system"
            name="ignition::gazebo::systems::ModelPhotoShoot">
            <translation_data_file>'$2'</translation_data_file>
            <random_joints_pose>'$3'</random_joints_pose>
        </plugin>
        </include>
        <model name="photo_shoot">
        <pose>2.2 0 0 0 0 -3.14</pose>
        <link name="link">
            <pose>0 0 0 0 0 0</pose>
            <sensor name="camera" type="camera">
            <camera>
                <horizontal_fov>1.047</horizontal_fov>
                <image>
                <width>960</width>
                <height>540</height>
                </image>
                <clip>
                <near>0.1</near>
                <far>100</far>
                </clip>
            </camera>
            <always_on>1</always_on>
            <update_rate>30</update_rate>
            <visualize>true</visualize>
            <topic>camera</topic>
            </sensor>
        </link>
        <static>true</static>
        </model>
    </world>
    </sdf>' > $4

) }

_test_models() { (
    source /usr/share/gazebo/setup.bash



    cd "$3"
    mkdir -p visual/model/
    cp -r "$1"/* visual/model/
    cd visual/model/
    sed -i 's/'"'"'/"/g' "$2"
    MODEL_NAME=`grep 'model name' model.sdf|cut -f2 -d '"'`
    sed -i "s,model://$MODEL_NAME/,,g" "$2"

    # Generate model pics using the gazebo plugin.
    mkdir -p $3/visual/pics/default_pose/
    cd "$3/visual/pics/default_pose/"
    _generate_sdf "$3/visual/model/$2" "$3/visual/pics/default_pose/poses.txt" "false" "$3/visual/pics/default_pose/plugin_config.sdf"
    ign gazebo -s -r "$3/visual/pics/default_pose/plugin_config.sdf" --iterations 50

    mkdir -p $3/visual/pics/random_pose/
    cd "$3/visual/pics/random_pose/"
    _generate_sdf "$3/visual/model/$2" "$3/visual/pics/random_pose/poses.txt" "true" "$3/visual/pics/random_pose/plugin_config.sdf"
    ign gazebo -s -r "$3/visual/pics/random_pose/plugin_config.sdf" --iterations 50

    # Generate model pics using drake then run
    # IoU tests and extra checks.
    cd ${_cur_dir}
    ./test_models.py "$1" "$2" "$3/visual/"

    # Test collision meshes:
    # Exchange visual and collision meshes in the model
    # in order to take pics of the collision mesh and
    # compare them.
    cd "$3"
    mkdir -p collisions/model/
    cp -r "$1"/* collisions/model/
    cd collisions/model/
    find . -name "*.mtl" | xargs rm
    sed -i 's/collision/temporalname/g' "$2"
    # Workaround to ignore the old collision tags
    sed -i 's/visual/ignore:collision/g' "$2"
    sed -i 's/temporalname/visual/g' "$2"

    sed -i 's/'"'"'/"/g' "$2"
    sed -i "s,model://$MODEL_NAME/,,g" "$2"

    # Generate model pics using the gazebo plugin.
    mkdir -p $3/collisions/pics/default_pose/
    cd "$3/collisions/pics/default_pose/"
    _generate_sdf "$3/collisions/model/$2" "$3/collisions/pics/default_pose/poses.txt" "false" "$3/collisions/pics/default_pose/plugin_config.sdf"
    ign gazebo -s -r "$3/collisions/pics/default_pose/plugin_config.sdf" --iterations 50

    mkdir -p $3/collisions/pics/random_pose/
    cd "$3/collisions/pics/random_pose/"
    _generate_sdf "$3/collisions/model/$2" "$3/collisions/pics/random_pose/poses.txt" "true" "$3/collisions/pics/random_pose/plugin_config.sdf"
    ign gazebo -s -r "$3/collisions/pics/random_pose/plugin_config.sdf" --iterations 50

    # Generate model pics using drake then run
    # IoU tests and extra checks.
    cd ${_cur_dir}
    ./test_models.py "$3/collisions/model/" "$2" "$3/collisions/"
) }

_preprocess_sdf_and_materials() { (
    #convert .stl and .dae entries to .obj
    sed -i 's/.stl/.obj/g' "$1/$2"
    sed -i 's/.dae/.obj/g' "$1/$2"
    # Some sdfs have a comment before the xml tag
    # this makes the parser fail, since the tag is optional
    # we'll remove it as safety workaround
    sed -i '/<?xml*/d' "$1/$2"

    find . -name '*.jpg' -type f -exec bash -c 'convert "$0" "${0%.jpg}.png"' {} \;
    find . -name '*.jpeg' -type f -exec bash -c 'convert "$0" "${0%.jpeg}.png"' {} \;

    find . -type f -name '*.mtl' -exec sed -i 's/.jpg/.png/g' '{}' \;
    find . -type f -name '*.mtl' -exec sed -i 's/.jpeg/.png/g' '{}' \;
) }

_provision_repos() { (
    set -eu
    cd ${_cur_dir}
    repo_dir=${PWD}/repos
    completion_token=2021-03-12.1
    completion_file=$1/.completion-token

    if [[ "$2" == *\.sdf ]]
    then
        _preprocess_sdf_and_materials "$1" "$2"
        ./render_ur_urdfs.py "$1" "$2"
    else
        if [[ -f ${completion_file} && "$(cat ${completion_file})" == "${completion_token}" ]]; then
        return 0
        fi
        set -x
        rm -rf ${repo_dir}

        mkdir ${repo_dir} && cd ${repo_dir}

        git clone https://github.com/ros-industrial/universal_robot
        cd universal_robot/
        git checkout e8234318cc94  # From melodic-devel-staging
        # Er... dunno what to do about this, so hackzzz
        cd ${_cur_dir}
        ./ros_setup.bash ./render_ur_urdfs.py "$1" "$2"
    fi

    echo "${completion_token}" > ${completion_file}
) }

_setup_venv() { (
    set -eu
    cd ${_cur_dir}
    completion_token="$(cat ./requirements.txt)"
    completion_file=${_venv_dir}/.completion-token

    if [[ -f ${completion_file} && "$(cat ${completion_file})" == "${completion_token}" ]]; then
        return 0
    fi

    set -x
    rm -rf ${_venv_dir}

    mkdir -p ${_venv_dir}
    tar -xzf $(_download_drake) -C ${_venv_dir} --strip-components=1

    # See: https://drake.mit.edu/from_binary.html#stable-releases
    python3 -m venv ${_venv_dir} --system-site-packages
    cd ${_venv_dir}
    ./bin/pip install -U pip wheel
    ./bin/pip install -r ${_cur_dir}/requirements.txt
    ./bin/pip freeze > ${_cur_dir}/requirements.freeze.txt

    echo "${completion_token}" > ${completion_file}
) }

if [[ $# -lt "2" ]]; then
    echo "Please provide path to model directory and model file name."
    echo "      Usage:"
    echo "                  $./setup.sh <model_directory_path> <model_file_name> ./[executable]"
    echo "      or"
    echo "                  $source ./setup.sh <model_directory_path> <model_file_name>"
    echo "                  $./[executable]"

    return 1
fi

temp_directory=$(mktemp -d)
echo "Saving temporal test files to: ${temp_directory}"

_setup_venv && source ${_venv_dir}/bin/activate

_provision_repos "$1" "$2"

_test_models "$1" "$2" "$temp_directory"

if [[ ${0} == ${BASH_SOURCE} ]]; then
    # This was executed, *not* sourced. Run arguments directly.
    set -eux
    #env
    exec "${@:3}"
else
    source /usr/share/gazebo/setup.bash
fi
