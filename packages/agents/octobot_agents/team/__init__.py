#  This file is part of OctoBot (https://github.com/Drakkar-Software/OctoBot)
#  Copyright (c) 2025 Drakkar-Software, All rights reserved.
#
#  OctoBot is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation; either
#  version 3.0 of the License, or (at your option) any later version.
#
#  OctoBot is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  General Public License for more details.
#
#  You should have received a copy of the GNU General Public
#  License along with OctoBot. If not, see <https://www.gnu.org/licenses/>.

from octobot_agents.team.team import (
    AbstractAgentTeamChannel,
    AbstractAgentTeamChannelProducer,
    AbstractAgentTeamChannelConsumer,
    AbstractSyncAgentTeamChannelProducer,
    AbstractLiveAgentTeamChannelProducer,
)

from octobot_agents.team.team_manager import (
    AbstractTeamManagerAgent,
    DefaultTeamManagerAgentProducer,
    AITeamManagerAgentProducer,
    DefaultTeamManagerAgentChannel,
    DefaultTeamManagerAgentConsumer,
    AITeamManagerAgentChannel,
    AITeamManagerAgentConsumer,
    ExecutionPlan,
    ExecutionStep,
    AgentInstruction,
    MODIFICATION_ADDITIONAL_INSTRUCTIONS,
    MODIFICATION_CUSTOM_PROMPT,
    MODIFICATION_EXECUTION_HINTS,
)

__all__ = [
    # Team classes
    "AbstractAgentTeamChannel",
    "AbstractAgentTeamChannelProducer",
    "AbstractAgentTeamChannelConsumer",
    "AbstractSyncAgentTeamChannelProducer",
    "AbstractLiveAgentTeamChannelProducer",
    # Manager classes
    "AbstractTeamManagerAgent",
    "DefaultTeamManagerAgentProducer",
    "AITeamManagerAgentProducer",
    "DefaultTeamManagerAgentChannel",
    "DefaultTeamManagerAgentConsumer",
    "AITeamManagerAgentChannel",
    "AITeamManagerAgentConsumer",
    # Models
    "ExecutionPlan",
    "ExecutionStep",
    "AgentInstruction",
    # Constants
    "MODIFICATION_ADDITIONAL_INSTRUCTIONS",
    "MODIFICATION_CUSTOM_PROMPT",
    "MODIFICATION_EXECUTION_HINTS",
]
