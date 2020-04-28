#!/usr/bin/env python3
import time

import numpy as np

import rospy

from pydrake.common import FindResourceOrThrow
from pydrake.systems.framework import DiagramBuilder
from pydrake.geometry import ConnectDrakeVisualizer
from pydrake.multibody.parsing import Parser
from pydrake.multibody.plant import AddMultibodyPlantSceneGraph
from pydrake.systems.analysis import Simulator
from pydrake.systems.primitives import ConstantVectorSource

from drake_ros1_rviz.rviz_visualizer import ConnectRvizVisualizer


def no_control(plant, builder, model):
    nu = plant.num_actuated_dofs(model)
    u0 = np.zeros(nu)
    constant = builder.AddSystem(ConstantVectorSource(u0))
    builder.Connect(
        constant.get_output_port(0),
        plant.get_actuation_input_port(model))


def main():
    sdf_file = FindResourceOrThrow(
        "drake/manipulation/models/iiwa_description/iiwa7/"
        "iiwa7_no_collision.sdf")
    builder = DiagramBuilder()
    plant, scene_graph = AddMultibodyPlantSceneGraph(builder, time_step=0.01)
    # TODO: Test multiple IIWAs.
    model = Parser(plant).AddModelFromFile(sdf_file)
    base_frame = plant.GetFrameByName("iiwa_link_0")
    plant.WeldFrames(plant.world_frame(), base_frame)
    plant.Finalize()
    no_control(plant, builder, model)

    ConnectDrakeVisualizer(builder, scene_graph)
    ConnectRvizVisualizer(builder, scene_graph)


    diagram = builder.Build()
    simulator = Simulator(diagram)
    context = simulator.get_mutable_context()
    simulator.set_target_realtime_rate(1.)

    # Wait for ROS publishers to wake up :(
    time.sleep(0.3)
    single_shot = False

    if single_shot:
        # To see what 'preview' scripts look like.
        simulator.Initialize()
        diagram.Publish(context)
    else:
        for _ in range(1000):
            simulator.AdvanceTo(context.get_time() + 0.1)


if __name__ == "__main__":
    rospy.init_node("demo", disable_signals=True)
    main()
