classdef AttackOnActuator < CyberPhysicalAttack
    % Physical attack to actuator. Actuator can be turned on, off. Settings
    % (nominal speed for pumps) can be altered.  
        
    % public methods
    methods
            
    function self = AttackOnActuator(...
            target, ini_condition, end_condition, args)   
        
        % one argument at most
        if numel(args) == 1
            setting = str2num(args{1});
        else
            error('AttackOnActuator: this class needs 1 argument only.');
        end
        
        % call superclass constructor
        self@CyberPhysicalAttack('PHY', target, ini_condition, end_condition, setting)
    end            
    
	function self = performAttack(self, varargin)
        % get arguments
		epanetSim = varargin{1};
        
        % get dummy controls
        dummyControls = epanetSim.epanetMap.dummyControls;
 
        % get attacked component and index
        thisComponent = self.target;
        thisIndex = EpanetHelper.getComponentIndex(thisComponent);
        
        % activate dummy control, save and exit        
        for i = 1 : numel(dummyControls)
            if dummyControls(i).lIndex == thisIndex
                self.actControl = i;
                return
            end  
        end                
    end 
    
	function [self, epanetSim] = stopAttack(self, varargin)
		% get arguments
		time 		= varargin{1};
		epanetSim 	= varargin{2};
		
        % attack is off        
        self.inplace = 0;
        self.endTime = epanetSim.symbolDict('TIME');
        
        % deactivate dummy control
        epanetSim.epanetMap.dummyControls(self.actControl) = ...
            epanetSim.epanetMap.dummyControls(self.actControl).deactivateWithValues(...
            int64(time));
    end
    
    function [self, epanetSim] = evaluateAttack(self, epanetSim)        
        if self.inplace == 0
            % attack is not active, check if starting condition met
            flag = self.evaluateStartingCondition(epanetSim.symbolDict);            
            if flag
                % start attack
                self = self.startAttack(...
                    int64(epanetSim.simTime + epanetSim.tstep),epanetSim);
                    
					% TO DO: should find a better way to perform dummy
                    % control activation, outside of this class.
                    epanetSim.epanetMap.dummyControls(self.actControl).isActive = 1;                     
            end
        else
            % attack is ongoing, check if ending condition is met for this attack
            flag = self.evaluateEndingCondition(epanetSim.symbolDict);
            if flag
                % stop attack
                [self, epanetSim] = self.stopAttack(...
					int64(epanetSim.simTime + epanetSim.tstep), epanetSim);
            end
        end
    end
    
    end
    
end
    