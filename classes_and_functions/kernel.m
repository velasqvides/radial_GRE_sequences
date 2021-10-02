classdef kernel < handle
    %UNTITLED Summary of this class goes here
    %   Detailed explanation goes here
    
    properties(Access = protected)
        protocol (1,1) protocol
    end
    
    methods
        
        function obj = kernel(inputProtocol)
            obj.protocol = inputProtocol;
        end
        
        function [RF, Gz, GzReph] = createSlabSelectionEvents(obj)
            RfExcitation = obj.protocol.RfExcitation;
            flipAngle = obj.protocol.flipAngle;
            RfPulseDuration = obj.protocol.RfPulseDuration;
            slabThickness = obj.protocol.slabThickness;
            RfPulseApodization = obj.protocol.RfPulseApodization;
            timeBwProduct = obj.protocol.timeBwProduct;
            systemLimits = obj.protocol.systemLimits;
            
            switch RfExcitation
                case 'selectiveSinc'
                    [RF, Gz, GzReph] = mr.makeSincPulse(flipAngle*pi/180,'Duration',RfPulseDuration,...
                        'SliceThickness',slabThickness,'apodization',RfPulseApodization,...
                        'timeBwProduct',timeBwProduct,'system',systemLimits);
                    
                case 'nonSelective'
                    RF = mr.makeBlockPulse(flipAngle*pi/180,systemLimits,'Duration',RfPulseDuration);
                    Gz = []; GzReph = [];
            end
            
        end % end of createSlabSelectionEvents
        
        function [Gx, GxPre, ADC] = createReadoutEvents(obj)
            nSamples = obj.protocol.nSamples;
            deltaKx = obj.protocol.deltaKx;
            systemLimits = obj.protocol.systemLimits;
            readoutOversampling = obj.protocol.readoutOversampling;
            dwellTime = obj.protocol.dwellTime;
            readoutGradientAmplitude = obj.protocol.readoutGradientAmplitude;
            readoutGradientFlatTime = obj.protocol.readoutGradientFlatTime;
            
            Gx = mr.makeTrapezoid('x','Amplitude',readoutGradientAmplitude,'FlatTime',...
                readoutGradientFlatTime,'system',systemLimits);
            % here I include some area (the last term) to make the trayectory asymmetric
            % and to measure the center ok k-space.
            GxPreArea = -(nSamples * deltaKx)/nSamples*(floor(nSamples/2)) - ...
                (Gx.riseTime*Gx.amplitude)/2 - 0.5*dwellTime*readoutGradientAmplitude;            
            GxPre = mr.makeTrapezoid('x','Area',GxPreArea,'system',systemLimits);
            ADC = mr.makeAdc(nSamples * readoutOversampling,'Dwell',dwellTime,'system',systemLimits);
        end % end of createReadoutEvents
        
        function [GxPlusSpoiler,dispersionPerTR] = createGxPlusSpoiler(obj)
            [Gx, GxPre, ~] = createReadoutEvents(obj);
            phaseDispersionReadout = obj.protocol.phaseDispersionReadout;
            systemLimits = obj.protocol.systemLimits;
            spatialResolution = obj.protocol.spatialResolution;
            gradRasterTime = obj.protocol.systemLimits.gradRasterTime;
            
            areaGxAfterTE = Gx.area - abs(GxPre.area);
            inherentDispersionAfterTE = obj.calculatePhaseDispersion(areaGxAfterTE,obj.protocol.spatialResolution);
            if phaseDispersionReadout <= inherentDispersionAfterTE
                GxPlusSpoiler = Gx; % add no extra area
            else
                areaSpoilingX = phaseDispersionReadout / (2 * pi * spatialResolution);
                extraAreaNeeded = areaSpoilingX - areaGxAfterTE;                
                extraFlatTimeNeeded = gradRasterTime * round((extraAreaNeeded / Gx.amplitude)/ gradRasterTime);
                GxPlusSpoiler = mr.makeTrapezoid('x','amplitude',Gx.amplitude,'FlatTime', ...
                    Gx.flatTime + extraFlatTimeNeeded,'system',systemLimits);
            end
            % since the extra flat time need to comply with the gradRaster time,
            % the exact desired phase dispersion cant be acchieved, but it will be close enough.
            dispersionPerTR = obj.calculatePhaseDispersion(GxPlusSpoiler.area-abs(GxPre.area), ...
                obj.protocol.spatialResolution);
        end % end GxPlusSpoiler       
           
    end % end methods
    
    
    methods(Static)
       function phaseDispersion = calculatePhaseDispersion(SpoilerArea, dimensionAlongSpoiler)
           phaseDispersion = 2 * pi * dimensionAlongSpoiler * SpoilerArea;
       end
   end
    
end % end class kernel

