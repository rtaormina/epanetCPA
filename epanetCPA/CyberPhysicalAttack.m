classdef CyberPhysicalAttack
    % Basic class for implementing cyber physical attacks.
	% All other attacks inherit from it.
      
    properties
        layer           % targeted layer (PHY,PLC,SCADA,CTRL)
        target          % targeted component
        ini_condition   % if condition true, attack starts
        end_condition   % if condition true, attack ends
        actControl      % control used for simulation
        deactControls   % controls deactivated for simulation
        setting         % actuator/control setting
        inplace         % 0 (no attack) or 1 (attack on)        
        iniTime         % when the attack starts
        endTime         % when the attack ends
    end
        
    
    % public methods
    methods
        
    % constructor
    function self = CyberPhysicalAttack(...
            layer, target, ini_condition, end_condition, setting )
        % store properties
        self.layer  = layer;
        self.target = target;
        self.ini_condition = ini_condition;
        self.end_condition = end_condition;        
        self.setting       = setting;        
        self.actControl    = [];
        self.deactControls = [];
        self.inplace = 0;        
    end
    
    % evaluate attack
    function self = evaluateAttack(varargin)
         % this is a prototype method!        
        error('Implement this method for subclass of CyberPhysicalAttack!')       
    end
    
    function self = startAttack(self, time, epanetSim)  
        % mark that the attack started
        self.inplace = 1;
        self.iniTime = time;          
        % perform attack
        self = self.performAttack(epanetSim);
    end
    
    % stop attack
    function self = stopAttack(varargin)       
        % this is a prototype method!        
        error('Implement this method for subclass of CyberPhysicalAttack!')
    end
    
    % perform attack
    function self = performAttack(varargin)       
        % this is a prototype method!        
        error('Implement this method for subclass of CyberPhysicalAttack!')
    end
        
    function flag = evaluateStartingCondition(self, symbolDict)       
        % Checks whether condition to start attack is verified or not.        
        
        % get condition
        thisCondition = self.ini_condition;
        % find vars
        vars = symvar(thisCondition);
        % evaluate each var
        for j = 1 : numel(vars)
            thisVar = vars{j};
            eval(sprintf('%s = symbolDict(''%s'');',thisVar,thisVar));
        end
        % evaluate condition
        flag = eval([thisCondition,';']);          
    end
    
    
    function flag = evaluateEndingCondition(self, symbolDict)       
		% Checks whether condition to end attack is verified or not.
        
        % get condition
        thisCondition = self.end_condition;
        % find vars
        vars = symvar(thisCondition);
        % evaluate each var
        for j = 1 : numel(vars)
            thisVar = vars{j};
            eval(sprintf('%s = symbolDict(''%s'');',thisVar,thisVar));
        end
        % evaluate condition        
        try
            flag = eval([thisCondition,';']);
        catch
            disp('Problem here!')
        end
    end
 
    end
end
    