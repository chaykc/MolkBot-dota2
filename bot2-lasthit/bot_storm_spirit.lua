

--[[ STORM SPIRIT BOT 2: LAST HITTING

This bot has precisely 2 actions:

-attack the lowest HP creep
-enter "wait" mode which is essentially to just maintain attack range distance from the
  lowest HP creep.
  
The states are somewhat more involved than storm spirit 1.
The state parameters:

Projectile Position
  The goal of this parameter is to try to identify post-attack states. Because ranged
  heroes do not deal damage to the creep for a few frames as the projectile travels
  to the target, it seemed impossible for the bot to ever attribute an attack to a
  reward. Without this parameter, the state prior to a "last hit" (and therefore a
  reward) would be identical to a state of just standing there while a creep is at low
  HP.. so rewards would propagate to unrelated states in my opinion. With this parameter,
  the state prior to a last hit will be a state with an in-air projectile very close to
  the creep. Over time, this reward should "crawl" backwards through projectile distance
  states and start influencing proper attack times.
  
  This state has 5 values:
  > 360 units distance from lowest HP creep, 240 - 360, 120 - 240, 0 - 120, "no projectile"
  
  I'm not sure if having "no projectile" in this state is a good idea. It might not
  translate nicely to a neural network this way.
  
Lowest HP Creep HP
  I decided to base this parameter not off of absolute values or percents but instead
  off of offset of storm spirits current attack damage. This should more accurately 
  capture the relation between a creep's absolute HP value in relation to storm's
  damage. As his damage goes up, he can begin his attack earlier in terms of the creep's
  absolute HP, but he cannot begin his attack earier in terms of the creep's HP minus
  storm's damage. (It should be minus, not divide)
  
  Eg: storm deals 50 damage: he can start his attack when creep has 60hp
      storm deals 500 damage, he can begin his attack when creep has 510hp
      however, in both examples, storm begins his attack when CREEPHP - ATCKDMG = 10
      
  This state has 5 values:
  creepHP - atckDmg < 0, creepHP - atckDmg = 0 to 10, 10 - 20, 20 - 30, > 30
  
  This parameter looks to be a great candidate for a neuron.
  
At the moment, this approach will not take into account storm's attack animation
or friendly creep dps. Normally, players will time their last hits to occur mere moments
after a friendly creep damages the target to within kill range. Therefore, I think
a sophisticated bot would somehow take into account how much damage your creeps
are currently doing to the target per second, or possible even track attack
animations for all your friendly creeps.

Rewards and Punishments:

  I am going to give a reward for a successful last hit. Also, I will give a
  negative reward to attacks that do damage to the creep but do not kill it.
  Otherwise I think storm will just constantly attack the creep as there is
  very little reason not to. Last hits are determined as follows:
  
  A creep dies and storm spirit's last hit count goes up
  
  An attack that damages but does not kill the creep will be determined as:
  
  Last frame a projectile was airborne and this frame the projectile is gone,
  but the creep is still alive and WasRecentlyDamagedByHero returns true.
  
Extra Notes:

  
]]
      
  
NUM_ACTIONS = 2; -- attack lowest HP creep, wait
NUM_STATES_PROJECTILE = 5;
STATES_PROJECTILE_BOUNDARIES = {360, 240, 120, 0};
NUM_STATES_CREEP_HP = 5;
STATES_CREEP_HP_BOUNDARIES = {30, 20, 10, 0};
lut = {};
epsilon = 0.1;
alpha = 0.01;
gamma = 0.4;

prevAction = nil;
prevProjectileState = nil;
prevCreepHPState = nil;

for i=1,NUM_STATES_PROJECTILE do
  lut[i] = {};
  for j=1,NUM_STATES_CREEP_HP do
    lut[i][j] = {};
    for k=1,NUM_ACTIONS do
      lut[i][j][k] = 0;
    end
  end
end

RADIANT_FOUNTAIN_COORDS = Vector(-6750,-6550,512);
RADIANT_TOWER_COORDS = Vector(-1250,-1250,512);

DIRE_FOUNTAIN_COORDS = Vector(6780,6124,512);
DIRE_TOWER_COORDS = Vector(640,500,0);

STORM_ATTACK_RANGE = 480;

lastGameTime = 0;
lastLastHits = 0;

PLAYER_NUM = nil;

projectileExistedLastFrame = false;
inAirProjectileTarget = nil;

STORM_PROJECTILE_SPEED = 1100;

initialized = false;

fountainCoords = nil;
towerCoords = nil;

FUN_GREEN_CIRCLE_RADIUSES = {25,50,75,100,125,150,175,200,225,250,275,300,325,350,375,349,324,299,274,249,224,199,194,149,124,99,74,49,24};
currentGreenCircleRadius = nil;

function Think()
  
  if (not initialized) then init(); end
  
  local thisGameTime = GameTime();
  local timeSinceLastTick = thisGameTime - lastGameTime;
  lastGameTime = thisGameTime;
  
  local npcBot = GetBot();
  PLAYER_NUM = npcBot:GetPlayerID();
  
  if (not npcBot:IsAlive()) then
    return;
  end
  
  local projectile_state = -1;
  local creep_hp_state = -1;
  local action = 1;
  
  local creepList = GetUnitList(UNIT_LIST_ENEMY_CREEPS);
  local lowestHPCreep = nil;
  local distanceClosestCreep = 999999;
  local closest2FountainCreep = nil;
  
  local qMax = 0;
  local reward = 0;
  
  for k,creep in pairs(creepList) do
    
    if (lowestHPCreep == nil or creep:GetHealth() < lowestHPCreep:GetHealth()) then
      
      lowestHPCreep = creep;
      
    end
    
    if (closest2FountainCreep == nil or GetUnitToLocationDistance(creep, fountainCoords) < distanceClosestCreep) then
      closest2FountainCreep = creep;
      distanceClosestCreep = GetUnitToLocationDistance(creep, fountainCoords);
    end
    
  end
  
  if (lowestHPCreep ~= nil) then
    
    projectile_state = DetermineProjectileState(npcBot, lowestHPCreep);
    creep_hp_state = DetermineCreepHPState(npcBot, lowestHPCreep);
    
    for i=1,NUM_ACTIONS do
      if (lut[projectile_state][creep_hp_state][i] > lut[projectile_state][creep_hp_state][action]) then
        action = i;
      end
    end
    
    --print(lut[projectile_state][creep_hp_state][1],lut[projectile_state][creep_hp_state][2]);
    
    qMax = lut[projectile_state][creep_hp_state][action];
    
    if (math.random() < epsilon) then
      action = math.random(1,NUM_ACTIONS);
    end
  else
    projectile_state = 5;
    action = 3;
  end
  
  reward = reward + 50000 * (npcBot:GetLastHits() - lastLastHits);
  
  if (projectile_state == 5 and projectileExistedLastFrame) then
    -- if there was a projectile last frame and now there isn't, assume
    -- it hit the target. if the target is still alive, it means the
    -- attack didn't kill the target so give a negative reward
    -- (if the target is dead, maybe the projectile never made it
    -- to the target so we wont give a negative reward)
    -- nasty side effect: uphill misses (no easy solution there)
    
    if (inAirProjectileTarget:IsAlive()) then
      reward = reward - 25000;
    end
  end
  
  if (reward ~= 0) then
    print("REWARD: " .. reward);
  end
  
  if (reward > 0) then
    currentGreenCircleRadius = 1;
  else
    if (currentGreenCircleRadius ~= nil) then
      currentGreenCircleRadius = currentGreenCircleRadius + 1;
      if (FUN_GREEN_CIRCLE_RADIUSES[currentGreenCircleRadius] == nil) then
        currentGreenCircleRadius = nil;
      else
        DebugDrawCircle(npcBot:GetLocation(), FUN_GREEN_CIRCLE_RADIUSES[currentGreenCircleRadius], 0, 255, 0);
      end
    end
  end
  
  if (prevAction ~= nil) then
    
    lut[prevProjectileState][prevCreepHPState][prevAction] = lut[prevProjectileState][prevCreepHPState][prevAction]
      + alpha * (reward + gamma * qMax - lut[prevProjectileState][prevCreepHPState][prevAction]);
    
  end
  
  if (action == 1) then
    npcBot:Action_AttackUnit(lowestHPCreep, false);
  elseif (action == 2) then
    if (GetUnitToUnitDistance(npcBot, closest2FountainCreep) < STORM_ATTACK_RANGE) then
      npcBot:Action_MoveDirectly(fountainCoords);
    else
      npcBot:Action_MoveDirectly(closest2FountainCreep:GetLocation());
    end
  else
    npcBot:Action_MoveToLocation(towerCoords);
  end
  
  if (action == 3) then
    prevAction = nil;
  else
    prevAction = action;
  end
  
  prevProjectileState = projectile_state;
  prevCreepHPState = creep_hp_state;
  lastLastHits = npcBot:GetLastHits();
  if (projectile_state ~= 5) then
    projectileExistedLastFrame = true;
    inAirProjectileTarget = lowestHPCreep;
  else
    projectileExistedLastFrame = false;
    inAirProjectileTarget = nil;
  end
end

function init()
  
  if (GetTeam() == TEAM_RADIANT) then
    fountainCoords = RADIANT_FOUNTAIN_COORDS;
    towerCoords = RADIANT_TOWER_COORDS;
  else
    fountainCoords = DIRE_FOUNTAIN_COORDS;
    towerCoords = DIRE_TOWER_COORDS;
  end
  
end

function DetermineProjectileState(hero, creep)
  
  local projectiles = creep:GetIncomingTrackingProjectiles();
  
  for k,v in pairs(projectiles) do
    
    if (v["caster"] == hero) then
            
      local projectileLocation = v["location"];
      
      local distance = GetUnitToLocationDistance(creep, projectileLocation);
      
      --print(distance, hero:GetAttackProjectileSpeed());
      
      for kk,boundary in pairs(STATES_PROJECTILE_BOUNDARIES) do
        
        if (distance > boundary) then return kk; end
        
      end
      
    end
    
  end
  
  return 5;
  
end

function DetermineCreepHPState(hero, creep)
  
  local heroDamage = creep:GetActualIncomingDamage(hero:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL);
  
  local creepHP = creep:GetHealth();
  
  local delta = creepHP - heroDamage;
  
  for k,boundary in pairs(STATES_CREEP_HP_BOUNDARIES) do
    
    if (delta > boundary) then return k; end
    
  end
  
  return 5;
  
end