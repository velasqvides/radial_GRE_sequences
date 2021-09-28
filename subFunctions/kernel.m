classdef kernel < handle
    %UNTITLED Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
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
            
        end
        
        function [Gx, GxPre, ADC] = createReadoutEvents(obj)
            nSamples = obj.protocol.nSamples;
            deltaKx = obj.protocol.deltaKx;
            systemLimits = obj.protocol.systemLimits;
            readoutOversampling = obj.protocol.readoutOversampling;
            dwellTime = obj.protocol.dwellTime;
            readoutGradientAmplitude = obj.protocol.readoutGradientAmplitude;
            readoutGradientFlatTime = obj.protocol.readoutGradientFlatTime;
            
            Gx = mr.makeTrapezoid('x','Amplitude',readoutGradientAmplitude,'FlatTime',readoutGradientFlatTime,'system',systemLimits);
            GxPreArea = -(nSamples * deltaKx)/nSamples*floor(nSamples/2) - (Gx.riseTime*Gx.amplitude)/2;
            GxPre = mr.makeTrapezoid('x','Area',GxPreArea,'system',systemLimits);
            ADC = mr.makeAdc(nSamples * readoutOversampling,'Dwell',dwellTime,'system',systemLimits);
        end
        
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
                GxPlusSpoiler = mr.makeTrapezoid('x','amplitude',Gx.amplitude,'FlatTime',Gx.flatTime + extraFlatTimeNeeded,'system',systemLimits);
            end
            dispersionPerTR = obj.calculatePhaseDispersion(GxPlusSpoiler.area-abs(GxPre.area), obj.protocol.spatialResolution);
        end
        
        function [delayTE, delayTR] = calculateTeAndTrDelays(obj)
            %calculateTeAndTrDelays calculates the TE and TR delays needed to add some
            %dead time in the sequence, in order to get the desired TE and TR
            %when they are not set to the minimum values.
            
            %             [TE_min, TR_min] = calculateMinTeTr(obj);
            %             TE = obj.protocol.TE;
            %             TR = obj.protocol.TR;
            %             gradRasterTime = obj.protocol.systemLimits.gradRasterTime;
            %
            %             delayTE = ceil( (TE - TE_min) / gradRasterTime ) * gradRasterTime;
            %             delayTR = ceil( (TR - TR_min - delayTE) / gradRasterTime ) * gradRasterTime;
            delayTE = 0;
            delayTR = 0;
        end
        
        
    end
    
    
    methods(Static)
       function phaseDispersion = calculatePhaseDispersion(SpoilerArea, dimensionAlongSpoiler)
           phaseDispersion = 2 * pi * dimensionAlongSpoiler * SpoilerArea;
       end
   end
    
end

