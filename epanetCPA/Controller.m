classdef Controller < matlab.mixin.Heterogeneous
    % Class implementing a controller (PLC, SCADA...)

    properties
        name                % controller identifier
        sensors             % list of sensors connected to controller
        actuators           % list of actuators controlled by controller
        sensorsIn           % list of sensors used to control the actuators
							% 	but sent by other controllers.
        controlsID          % list of controls IDs of this controller 
							% 	TO DO: see whether transfer all controls in this class rather
                            %   than keep them in EpanetCPAMap
    end
        
    methods
    
    % constructor
    function self = Controller(controllerInfo, controls)
        % creates controller instance from info
        self.name        = controllerInfo.name;
        self.sensors     = controllerInfo.sensors;
        self.actuators   = controllerInfo.actuators;
        
        % get sensorsIn by reading controls
        self = self.getControls(controls);
    end
   
    % end of public methods
    
    function self = addSensorIn(self, sensor)
        self.sensorsIn = cat(2, self.sensorsIn, sensor);
    end
    
    end
    
    
    
    % private methods
    methods (Sealed)
    
    function self = getControls(self, controls)
        % get controller controls from Map list
        self.sensorsIn = {}; self.controlsID = [];
        for i = 1 : numel(controls)
            thisActuator = EpanetHelper.getComponentId(controls(i).lIndex, 0);
            if ismember(thisActuator, self.actuators)
                % retrieve control ID
                self.controlsID = cat(1, self.controlsID, i);   
                
                % OVERRIDE DUE TO CYBER LINKS                
%                 % see if node is read by controller or reading is from another controller
%                 thisSensor = EpanetHelper.getComponentId(controls(i).nIndex, 1);
%                 if ~ismember(thisSensor, self.sensors)
%                     % is coming from another controller, add to sensorsIn
%                     % (add P_ since we have water levels and pressures)
%                     self.sensorsIn = cat(2, self.sensorsIn, ['P_',thisSensor]);            
%                 end                
            end
        end
        
        % remove redundant sensorsIn
        if ~isempty(self.sensorsIn)
            self.sensorsIn = unique(self.sensorsIn);        
        end
    end        

    % end of private methods
    end
    
end
