classdef SCADA < Controller
    % Class implementing SCADA system.  
    
    methods
    
    % constructor
    function self = SCADA(SCADAinfo, controls, allSensors)
        if isempty(SCADAinfo)
            % populate SCADA if not specified in .cpa file
            SCADAinfo.name  = 'SCADA';
            SCADAinfo.sensors     = {};
            SCADAinfo.actuators   = {};
        end
        
        % invoke superclass constructors
        self@Controller(SCADAinfo, controls);
        
%         % add all remaining sensors (i.e., SCADA always sees all)
%         self.sensorsIn = setdiff(allSensors,self.sensors);        
    end
   
    % end of public methods
    end
    
end
