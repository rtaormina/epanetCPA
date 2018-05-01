classdef AttackToControl < CyberPhysicalAttack   
    % Class implementing attack changing control logic.
        
    properties                
        isNode          % are we modifying the link or node setting of control?
        deact_setting   % control setting (when deactivated)        
    end
        
    
    % public methods
    methods
        
    % constructor
    function self = AttackToControl(...
            target, ini_condition, end_condition, args)
        % get the attack target
        % it comes as a string of the format "CTRLxt"
        % where:
        % x     is the number of the attacked control
        % t     is either "n" or "l", depending whether the attack changes 
        %       the controlling node or controlled link setting          
        expression = '\d+';
        [temp,ix1,ix2] = regexp(target,expression,'split');
        controlIx = str2num(target(ix1:ix2));        
        if ~strcmp(temp{1},'CTRL')
            error('Target must start with CTRL')       
        end
        
        if numel(args)>1
            error('Wrong number of arguments specified for AttackToControl');
        else
            setting = str2num(args{1});
        end
        
        % call superclass constructor
        self@CyberPhysicalAttack(...
            'CTRL', controlIx, ini_condition, end_condition,setting);
        
        % check if is a node or a link setting to be changed
        if strcmp(temp{2},'n')
            self.isNode = true;
        elseif strcmp(temp{2},'l')
            self.isNode = false;
        end 
        % initialize deact_setting
        self.deact_setting = [];
    end
                
    function [self,controls] = startAttack(self, time, epanetSim)                
        % mark that the attack started
        self.inplace = 1;
        self.iniTime = time;          

        % get controls
        controls = epanetSim.epanetMap.controls;
        
        % store original value
        if self.isNode
            self.deact_setting = controls(self.target).nSetting; 
        else
            self.deact_setting = controls(self.target).lSetting; 
        end
        
        % perform attack
        [self, controls] = self.performAttack(controls);
    end
    
    function [self,controls] = performAttack(self, varargin) 
        % get arguments
		controls = varargin{1};		
        if self.isNode
            % change original value (node)
            controls(self.target).nSetting =...
                single(self.setting);
        else
            % change original value (link)
            controls(self.target).lSetting =...
                single(self.setting);
        end
    end
        
	function [self,controls] = stopAttack(self, varargin)
		% get arguments
		time 		= varargin{1};
		epanetSim 	= varargin{2};		
        % attack is off
        self.inplace = 0;
        self.endTime = time;                   
        % get controls
        controls = epanetSim.epanetMap.controls;		
        if self.isNode
            % change original value (node)
            controls(self.target).nSetting =...
                single(self.deact_setting);
        else
            % change original value (link)
            controls(self.target).lSetting =...
                single(self.deact_setting);
        end
    end
    
	function [self, epanetSim] = evaluateAttack(self, epanetSim)
		if self.inplace == 0
			% attack is not active, check if starting condition met
			flag = self.evaluateStartingCondition(epanetSim.symbolDict);            
			if flag
				% start attack
				[self, epanetSim.epanetMap.controls] = ...
					self.startAttack(epanetSim.symbolDict('TIME'),epanetSim);
			end
		else
			% attack is ongoing
			% check if ending condition is met for this attack
			flag = self.evaluateEndingCondition(epanetSim.symbolDict);
			if flag
				% stop attack
				[self, epanetSim.epanetMap.controls] = ...
					self.stopAttack(epanetSim.symbolDict('TIME'),epanetSim);       
			end
		end 
    end
        
    end
    
end
    