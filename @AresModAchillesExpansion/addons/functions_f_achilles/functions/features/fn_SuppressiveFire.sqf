////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//	AUTHOR: Kex, CreepPork_LV
//	DATE: 22/12/17
//	VERSION: 1.1
//  DESCRIPTION: Forces the group of the given unit to suppress the given target
//
//	ARGUMENTS:
//	_this select 0:		OBJECT	- Unit that is injured
//	_this select 1:		ARRAY	- Target position given in world position (see getPosWorld)
//  _this select 2:		STRING	- Weapon muzzle to fire
//	_this select 3:		SCALAR	- (optional) Stance index: 0:prone, 1:crouch, 2:stand (0 by default)
//	_this select 4:		BOOL	- (optional) Line up before firing (false by default)
//	_this select 5:		SCALAR	- (optional) Stance index: 0:auto, 1:burst, 2:single, 3:talking guns (0 by default)
//	_this select 6:		SCALAR	- (optional) Duration in sec (10 by default)
//
//	RETURNS:
//	nothing (procedure)
//
//	Example:
//	[_unit,_worldPos, _weaponToFire] call Achilles_fnc_SuppressiveFire; // group goes prone and use automatic fire on target for 10 sec
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

params [["_unit",objNull,[objNull]],["_targetPos",[0,0,0],[[]]],["_weaponToFire", 0, [0]],["_stanceIndex",0,[0]],["_doLineUp",false,[false]],["_fireModeIndex",0,[0]],["_duration",10,[0]]];

private _old_group = group _unit;
private _units = units _old_group;

//create target logic
private _selectedTarget = (createGroup sideLogic) createUnit ["Module_f", [0,0,0], [], 0, "NONE"];
_selectedTarget setPosWorld _targetPos;

//save and remove waypoints
private _current_wp_id = currentWaypoint _old_group;
private _waypoint_count = count waypoints _old_group;
private _waypoints = [];
private "_start_wp_pos";
if (_current_wp_id < _waypoint_count) then
{
	for "_i" from (_waypoint_count - 1) to 1 step -1 do
	{
		_waypoints pushBack
		[
			waypointPosition [_old_group, _i],
			waypointType [_old_group, _i],
			waypointBehaviour [_old_group, _i],
			waypointCombatMode [_old_group, _i],
			waypointFormation [_old_group, _i],
			waypointSpeed [_old_group, _i],
			waypointScript [_old_group, _i]
		];
		deleteWaypoint [_old_group, _i];
	};
	_start_wp_pos = waypointPosition [_old_group, 0];
	[_old_group, 0] setWaypointPosition [position leader _old_group, 0];
	_old_group setCurrentWaypoint [_old_group, 0];
};

// force unit to change formation if not in combat
private _oldFormation = formation _old_group;
if (_doLineUp) then
{
	// set formation
	_old_group setBehaviour "AWARE";
	_units apply {_x setUnitPos "MIDDLE"};
	if (formation _old_group != "LINE") then
	{
		_old_group setFormation "LINE";
		// wait until unit is in formation
		sleep 2;
		waitUntil {sleep 1; {(speed _x > 0) and (alive _x)} count _units == 0};
	};
	// orientate line perpendicular to target
	_old_group setFormDir (_old_group getDir _selectedTarget);
	// wait until unit is in formation
	sleep 2;
	waitUntil {sleep 1; {(speed _x > 0) and (alive _x)} count _units == 0};
	_units apply {_x setUnitPos "AUTO"};
};

// get rid of vehicle crew except gunner
_units = _units select {gunner vehicle _x == _x};

// store original group in place holder
private _placeholder = _old_group createUnit ["B_Story_Protagonist_F", [0,0,0], [], 0, "NONE"];
_placeholder setPos [0,0,0];

{
	[_x, _units, _selectedTarget, _stanceIndex, _fireModeIndex, _duration, _placeholder, _weaponToFire] spawn
	{
		params
		[
			"_unit",
			"_units",
			"_target",
			"_stanceIndex",
			"_fireModeIndex",
			"_duration",
			"_placeholder",
			"_weaponToFire"
		];
		_unit = gunner _unit;

		// Find and make usage of the selected weapon by user.
		private _weapons = [];
		if (isNull objectParent _unit) then
		{
			{
				if !(_x isEqualTo "") then
				{
					diag_log _x;
					private _muzzleArray = getArray (configFile >> "CfgWeapons" >> _x >> "muzzles");
					if (count _muzzleArray > 1) then
					{
						{
							_weapons pushBack _x;
						} forEach _muzzleArray;
					}
					else
					{
						_weapons pushBack _x;
					};
				};
			} forEach [primaryWeapon _unit]; //TODO: Bug with pistol
		}
		else
		{
			private _vehicle = vehicle _unit;
			{
				if !(_x isEqualTo "") then
				{
					private _muzzleArray = getArray (configFile >> "CfgWeapons" >> _x >> "muzzles");
					if (count _muzzleArray > 1) then
					{
						{
							_weapons pushBack _x;
						} forEach _muzzleArray;
					}
					else
					{
						_weapons pushBack _x;
					};
				};
			} forEach (_vehicle weaponsTurret [0]);
		};

		private _muzzle = _weapons select _weaponToFire;

		// cease fire if group mate is too close to line of fire
		if (!([_unit, _target, _units - [_unit], 2] call Achilles_fnc_checkLineOfFire2D)) exitWith {};

		private _old_group = group _placeholder;
		private _aiming = _unit skill "aimingAccuracy";
		_unit setSkill ["aimingAccuracy", 0.2];
		_unit setUnitPos (["DOWN","MIDDLE","UP"] select _stanceIndex);

		// get fire mode parameters
		private _params = [[10,0],[3,0.7],[1,0.9]] select _fireModeIndex;
		_params params ["_fireRepeater", "_ceaseFireTime"];

		private _new_group = createGroup (side _unit);
		[_unit] join _new_group;
		_new_group setBehaviour "COMBAT";

		_unit doWatch objNull;
		_unit doWatch _target;
		_unit doTarget _target;
		_unit doTarget _target;
		_unit lookAt _target;

		//ensure asynchronous fire within a group
		sleep (random [2,3,4]);

		if (isNull objectParent _unit) then
		{
			
			for "_" from 1 to _duration do
			{
				for "_" from 1 to _fireRepeater do
				{
					sleep 0.1;
					[_unit, _muzzle] call BIS_fnc_fire;
					_unit setVehicleAmmo 1;
				};
				sleep _ceaseFireTime;
			};
		}
		else
		{
			private _vehicle = vehicle _unit;
			if (_unit == gunner _vehicle) then
			{
				for "_" from 0 to _duration do
				{
					for "_" from 1 to _fireRepeater do
					{
						_unit lookAt _target;
						sleep 0.1;
						_unit fireAtTarget [_vehicle, _muzzle];
						_vehicle setVehicleAmmo 1;
					};
					sleep _ceaseFireTime;
				};
			};
		};
		_unit setSkill ["aimingAccuracy", _aiming];
		_unit setUnitPos "AUTO";
		_units joinSilent _old_group;
		_old_group setBehaviour "AWARE";
		deleteVehicle _placeholder;
	};
} forEach _units;

//clean up
sleep (_duration + 5);
deleteVehicle _selectedTarget;
if (!isNull _old_group) then {_old_group setFormation _oldFormation};
[] spawn {{deleteGroup _x} forEach (allGroups select {units _x isEqualTo []})};
if (count _waypoints > 0 and !(isNull _old_group)) then
{
	reverse _waypoints;
	{
		private _wp = _old_group addWaypoint [_x select 0, 0];
		_wp setWaypointType (_x select 1);
		_wp setWaypointBehaviour (_x select 2);
		_wp setWaypointCombatMode (_x select 3);
		_wp setWaypointFormation (_x select 4);
		_wp setWaypointSpeed (_x select 5);
		_wp setWaypointScript (_x select 6);
	} forEach _waypoints;
	[_old_group, 0] setWaypointPosition [_start_wp_pos, 0];
	_old_group setCurrentWaypoint [_old_group, _current_wp_id];
};
