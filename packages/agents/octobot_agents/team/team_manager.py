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
"""
Team manager agent classes for orchestrating team execution.

Managers are responsible for the execution process of teams. They can be:
- DefaultTeamManagerAgent: Simple agent that executes in topological order
- AITeamManagerAgent: AI-powered agent that uses LLM to decide execution flow
"""
import abc
import typing
from typing import Dict, List, Optional, Union

from pydantic import BaseModel

import octobot_commons.logging as logging

from octobot_agents.channel import (
    AbstractAgentChannel,
    AbstractAgentChannelConsumer,
    AbstractAgentChannelProducer,
    AbstractAIAgentChannelProducer,
    AbstractAIAgentChannelConsumer,
)


# =============================================================================
# Modification Constants
# =============================================================================

MODIFICATION_ADDITIONAL_INSTRUCTIONS = "additional_instructions"
MODIFICATION_CUSTOM_PROMPT = "custom_prompt"
MODIFICATION_EXECUTION_HINTS = "execution_hints"


# =============================================================================
# Pydantic Models for Execution Plan
# =============================================================================

class AgentInstruction(BaseModel):
    """Instruction to send to an agent via channel.modify()"""
    modification_type: str  # One of MODIFICATION_ADDITIONAL_INSTRUCTIONS, MODIFICATION_CUSTOM_PROMPT, etc.
    value: Union[str, Dict[str, typing.Any]]  # The instruction content (string for prompts, dict for hints)


class ExecutionStep(BaseModel):
    """Single step in the execution plan"""
    agent_name: str
    instructions: Optional[List[AgentInstruction]] = None  # Instructions to send before execution
    wait_for: Optional[List[str]] = None  # Agent names to wait for before executing
    skip: bool = False  # Skip this agent in this iteration


class ExecutionPlan(BaseModel):
    """Complete execution plan - returned by both DefaultTeamManagerAgent and AITeamManagerAgent"""
    steps: List[ExecutionStep]
    loop: bool = False  # Whether to loop execution
    loop_condition: Optional[str] = None  # Condition description for looping
    max_iterations: Optional[int] = None  # Maximum loop iterations


# =============================================================================
# Abstract Team Manager Agent
# =============================================================================

class AbstractTeamManagerAgent(abc.ABC):
    """
    Base interface for all team managers.
    
    Both managers are agents and follow the agent pattern with channels.
    """
    
    def __init__(self):
        """Initialize the team manager agent."""
        self.logger = logging.get_logger(self.__class__.__name__)
    
    @abc.abstractmethod
    async def execute(self, input_data: typing.Any, ai_service: typing.Any) -> ExecutionPlan:
        """
        Execute the manager's logic and return an execution plan.
        
        Args:
            input_data: Contains {"team_producer": team_producer, "initial_data": initial_data, "instructions": instructions}
            ai_service: The AI service instance (for AI managers)
            
        Returns:
            ExecutionPlan with steps for team execution
        """
        raise NotImplementedError("execute must be implemented by subclasses")
    
    async def send_instruction_to_agent(
        self,
        agent: AbstractAIAgentChannelProducer,
        instruction: Dict[str, typing.Any],
    ) -> None:
        """
        Send instruction to an agent via channel.modify().
        
        Args:
            agent: The agent producer to send instructions to
            instruction: Dict with modification constants as keys (e.g., {MODIFICATION_ADDITIONAL_INSTRUCTIONS: "..."})
        """
        if agent.channel is None:
            self.logger.warning(f"Agent {agent.AGENT_NAME} has no channel, cannot send instructions")
            return
        
        await agent.channel.modify(**instruction)


# =============================================================================
# Default Team Manager Agent (Non-AI)
# =============================================================================

class DefaultTeamManagerAgentChannel(AbstractAgentChannel):
    """Channel for default team manager."""
    pass


class DefaultTeamManagerAgentConsumer(AbstractAgentChannelConsumer):
    """Consumer for default team manager."""
    pass


class DefaultTeamManagerAgentProducer(AbstractAgentChannelProducer, AbstractTeamManagerAgent):
    """
    Default team manager agent - simple agent that executes in topological order.
    
    Inherits from AbstractAgentChannelProducer AND AbstractTeamManagerAgent.
    Has Channel, Producer, Consumer components (as all agents do).
    """
    
    AGENT_NAME: str = "DefaultTeamManagerAgent"
    AGENT_CHANNEL: typing.Type[AbstractAgentChannel] = DefaultTeamManagerAgentChannel
    AGENT_CONSUMER: typing.Type[AbstractAgentChannelConsumer] = DefaultTeamManagerAgentConsumer
    
    def __init__(
        self,
        channel: typing.Optional[DefaultTeamManagerAgentChannel] = None,
    ):
        AbstractTeamManagerAgent.__init__(self)
        AbstractAgentChannelProducer.__init__(self, channel)
    
    async def execute(self, input_data: typing.Any, ai_service: typing.Any) -> ExecutionPlan:
        """
        Build execution plan from topological sort.
        
        Args:
            input_data: Contains {"team_producer": team_producer, "initial_data": initial_data, "instructions": instructions}
            ai_service: Not used by default manager
            
        Returns:
            ExecutionPlan with steps in topological order
        """
        team_producer = input_data.get("team_producer")
        if team_producer is None:
            raise ValueError("team_producer is required in input_data")
        
        # Get execution order (topological sort)
        execution_order = team_producer._get_execution_order()
        incoming_edges, _ = team_producer._build_dag()
        
        # Build ExecutionPlan
        steps: List[ExecutionStep] = []
        for agent in execution_order:
            # Get predecessors for wait_for
            channel_type = agent.AGENT_CHANNEL
            if channel_type is None:
                continue
            
            predecessors = incoming_edges.get(channel_type, [])
            wait_for: Optional[List[str]] = None
            if predecessors:
                wait_for = []
                for pred_channel in predecessors:
                    pred_agent = team_producer._producer_by_channel.get(pred_channel)
                    if pred_agent:
                        wait_for.append(pred_agent.AGENT_NAME)
            
            step = ExecutionStep(
                agent_name=agent.AGENT_NAME,
                instructions=None,  # No instructions by default
                wait_for=wait_for,
                skip=False,
            )
            steps.append(step)
        
        return ExecutionPlan(
            steps=steps,
            loop=False,
            loop_condition=None,
            max_iterations=None,
        )


# =============================================================================
# AI Team Manager Agent
# =============================================================================

class AITeamManagerAgentChannel(AbstractAgentChannel):
    """Channel for AI team manager."""
    pass


class AITeamManagerAgentConsumer(AbstractAgentChannelConsumer):
    """Consumer for AI team manager."""
    pass


class AITeamManagerAgentProducer(AbstractAIAgentChannelProducer, AbstractTeamManagerAgent):
    """
    AI team manager agent - uses LLM to decide execution flow.
    
    Inherits from AbstractAIAgentChannelProducer AND AbstractTeamManagerAgent.
    Has Channel, Producer, Consumer components (as all AI agents do).
    """
    
    AGENT_NAME: str = "AITeamManagerAgent"
    AGENT_CHANNEL: typing.Type[AbstractAgentChannel] = AITeamManagerAgentChannel
    AGENT_CONSUMER: typing.Type[AbstractAgentChannelConsumer] = AITeamManagerAgentConsumer
    
    def __init__(
        self,
        channel: typing.Optional[AITeamManagerAgentChannel] = None,
        model: typing.Optional[str] = None,
        max_tokens: typing.Optional[int] = None,
        temperature: typing.Optional[float] = None,
    ):
        AbstractTeamManagerAgent.__init__(self)
        AbstractAIAgentChannelProducer.__init__(self, channel, model=model, max_tokens=max_tokens, temperature=temperature)
    
    def _get_default_prompt(self) -> str:
        """
        Return the default prompt for the AI team manager.
        
        Returns:
            The default system prompt string.
        """
        return """You are a team execution manager for an agent team system.
Your role is to analyze the team structure, current state, and any instructions,
then create an execution plan that determines:
1. Which agents to execute
2. In what order
3. What instructions to send to each agent
4. Whether to loop execution

The execution plan should optimize for the team's goals while respecting dependencies."""
    
    async def execute(self, input_data: typing.Any, ai_service: typing.Any) -> ExecutionPlan:
        """
        Build execution plan using LLM.
        
        Args:
            input_data: Contains {"team_producer": team_producer, "initial_data": initial_data, "instructions": instructions}
            ai_service: The AI service instance for LLM calls
            
        Returns:
            ExecutionPlan from LLM
        """
        team_producer = input_data.get("team_producer")
        initial_data = input_data.get("initial_data", {})
        instructions = input_data.get("instructions")
        
        if team_producer is None:
            raise ValueError("team_producer is required in input_data")
        
        # Build context
        agents_info = []
        for agent in team_producer.agents:
            agents_info.append({
                "name": agent.AGENT_NAME,
                "channel": agent.AGENT_CHANNEL.__name__ if agent.AGENT_CHANNEL else None,
            })
        
        relations_info = []
        for source_channel, target_channel in team_producer.relations:
            relations_info.append({
                "source": source_channel.__name__,
                "target": target_channel.__name__,
            })
        
        context = {
            "team_name": team_producer.team_name,
            "agents": agents_info,
            "relations": relations_info,
            "initial_data": initial_data,
            "instructions": instructions,
        }
        
        # Build messages for LLM
        messages = [
            {"role": "system", "content": self.prompt},
            {
                "role": "user",
                "content": f"""Analyze the following team structure and create an execution plan:

Team: {team_producer.team_name}
Agents: {self.format_data(agents_info)}
Relations: {self.format_data(relations_info)}
Initial Data: {self.format_data(initial_data)}
Instructions: {self.format_data(instructions) if instructions else "None"}

Create an execution plan that determines the order and instructions for each agent."""
            },
        ]
        
        # Call LLM with ExecutionPlan as response schema
        response_data = await self._call_llm(
            messages,
            ai_service,
            json_output=True,
            response_schema=ExecutionPlan,
        )
        
        # Parse into ExecutionPlan model
        execution_plan = ExecutionPlan(**response_data)
        
        self.logger.info(f"Generated execution plan with {len(execution_plan.steps)} steps")
        
        return execution_plan
