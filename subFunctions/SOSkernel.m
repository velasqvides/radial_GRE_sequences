classdef SOSkernel < kernel
    %UNTITLED Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        Property1
    end
    
    methods
        
        function GzPartitionMax = createGzPartitionMax(obj)
            nPartitions = obj.protocol.nPartitions;
            systemLimits = obj.protocol.systemLimits;
            deltaKz = obj.protocol.deltaKz;
            
            GzPartitionArea = (-nPartitions/2) * deltaKz; % Max area
            % get a dummy gradient with the maximum area of all GzPartitions
            GzPartitionMax = mr.makeTrapezoid('z',systemLimits,'Area',GzPartitionArea);
        end
        
        function GzPartitionsCell = createAllGzPartitions(obj)
            nPartitions = obj.protocol.nPartitions;
            systemLimits = obj.protocol.systemLimits;
            deltaKz = obj.protocol.deltaKz;
            GzPartitionMax = createGzPartitionMax(obj);
            
            GzPartitionAreas = ((0:nPartitions-1) - nPartitions/2) * deltaKz; % areas go from bottom to top
            fixedGradientDuration = mr.calcDuration(GzPartitionMax);
            
            % make partition encoding gradients
            GzPartitionsCell = cell(1,nPartitions);
            for iz = 1:nPartitions
                GzPartitionsCell{iz} = mr.makeTrapezoid('z',systemLimits,'Area',GzPartitionAreas(iz),'Duration',fixedGradientDuration);
            end
            
        end
        
        function GzRephPlusPartitionsCell = createGzRephPlusPartitions(obj)
            nPartitions = obj.protocol.nPartitions;
            systemLimits = obj.protocol.systemLimits;
            deltaKz = obj.protocol.deltaKz;
            [~, ~, GzReph] = obj.createSlabSelectionEvents;
            if isempty(GzReph)
                GzRephArea = 0;
            else
                GzRephArea = GzReph.area;
            end
            
            GzPartitionAreas = ((0:nPartitions-1) - nPartitions/2) * deltaKz; % areas go from bottom to top
            % get a dummy gradient with the maximum area of all GzPartitions
            dummyGradient = mr.makeTrapezoid('z',systemLimits,'Area',max(abs(GzPartitionAreas)) + abs(GzRephArea));
            % Use the duration of the dummy gradient for all the GzPartitions to keep
            % the TE and TR constant.
            fixedGradientDuration = mr.calcDuration(dummyGradient);
            
            GzRephPlusPartitionsCell = cell(1,nPartitions);
            for iz = 1:nPartitions
                % here, the area of the slab-rephasing lobe and partition-encoding lobes are added together
                GzRephPlusPartitionsCell{iz} = mr.makeTrapezoid('z',systemLimits,'Area',GzPartitionAreas(iz) + GzRephArea,...
                    'Duration',fixedGradientDuration);
            end
            
        end
        
        function GzCombinedCell = combineGzWithGzRephPlusPartitions(obj)
            nPartitions = obj.protocol.nPartitions;
            systemLimits = obj.protocol.systemLimits;
            [~, Gz, ~] = obj.createSlabSelectionEvents(obj);
            GzRephPlusPartitionsCell = createGzRephPlusPartitions(obj);
            
            GzCombinedCell = cell(1,nPartitions);
            for iz=1:nPartitions
                GzCombinedCell{iz} = mr.addGradients({Gz, GzRephPlusPartitionsCell{iz}}, 'system', systemLimits);
            end
        end
        
        function [GzSpoilersCell, dispersionPerTR] = createGzSpoilers(obj)
            
            phaseDispersionZ = obj.protocol.phaseDispersionZ;
            nPartitions = obj.protocol.nPartitions;
            systemLimits = obj.protocol.systemLimits;
            partitionThickness = obj.protocol.partitionThickness;
            
            GzPartitionsCell = createAllGzPartitions(obj);
            GzPartitionMax = createGzPartitionMax(obj);
            dispersionDueToGzPartitionMax = 2 * pi * partitionThickness * abs(GzPartitionMax.area);
            
            GzSpoilersCell = cell(1,nPartitions);
            dispersionPerTR = zeros(1,nPartitions);
            
            if phaseDispersionZ == 0 % just refocuse the phase encoding gradient in Z direction
                duration = mr.calcDuration(GzPartitionMax);
                for iz = 1:nPartitions
                    GzSpoilersCell{iz} = mr.makeTrapezoid('z',systemLimits,'Area',-GzPartitionsCell{iz}.area,'Duration',duration);
                    areaTotal = GzPartitionsCell{iz}.area + GzSpoilersCell{iz}.area;
                    dispersionPerTR(iz) = 2 * pi * partitionThickness * areaTotal;
                end
                
            elseif phaseDispersionZ >= dispersionDueToGzPartitionMax
                % use the same duration to keep same TR
                AreaSpoilingZ_max = phaseDispersionZ / (2 * pi * partitionThickness);
                dummyGradient = mr.makeTrapezoid('z',systemLimits,'Area',abs(AreaSpoilingZ_max));
                fixedDurationGradient = mr.calcDuration(dummyGradient);                
                for iZ=1:nPartitions
                    % GzPartition already add some phase dispersion to the spins
                    dispersionDueToThisPartition = 2 * pi * partitionThickness * abs(GzPartitionsCell{iZ}.area);
                    % Then we calculate the phase dispersion needed to get phaseDispersionZ in total
                    dispersionNeededZ = abs(phaseDispersionZ - dispersionDueToThisPartition);
                    AreaSpoilingNeededZ = dispersionNeededZ / (2 * pi * partitionThickness);
                    if GzPartitionsCell{iZ}.area < 0
                        GzSpoilersCell{iZ} = mr.makeTrapezoid('z','Area',-AreaSpoilingNeededZ,'Duration',fixedDurationGradient,'system',systemLimits);
                    else
                        GzSpoilersCell{iZ} = mr.makeTrapezoid('z','Area',AreaSpoilingNeededZ,'Duration',fixedDurationGradient,'system',systemLimits);
                    end
                    areaTotal = GzPartitionsCell{iZ}.area + GzSpoilersCell{iZ}.area;
                    dispersionPerTR(iZ) = 2 * pi * partitionThickness * areaTotal;
                end
                
            else
                if phaseDispersionZ >= dispersionDueToGzPartitionMax/2
                    % use the same duration to keep same TR
                    AreaSpoilingZ_max = phaseDispersionZ / (2 * pi * partitionThickness);
                    dummyGradient = mr.makeTrapezoid('z',systemLimits,'Area',abs(AreaSpoilingZ_max));
                    fixedDurationGradient = mr.calcDuration(dummyGradient);
                else
                    AreaSpoilingZ_max = abs(phaseDispersionZ-dispersionDueToGzPartitionMax) / (2 * pi * partitionThickness);
                    dummyGradient = mr.makeTrapezoid('z',systemLimits,'Area',abs(AreaSpoilingZ_max));
                    fixedDurationGradient = mr.calcDuration(dummyGradient);
                end
                for ii=1:nPartitions
                    % GzPartition already add some phase dispersion to the spins
                    dispersionDueToThisPartition = 2 * pi * partitionThickness * abs(GzPartitionsCell{ii}.area);
                    % Then we calculate the phase dispersion needed to get phaseDispersionZ in total
                    dispersionNeededZ = abs(phaseDispersionZ - dispersionDueToThisPartition);
                    AreaSpoilingNeededZ = dispersionNeededZ / (2 * pi * partitionThickness);
                    haveSameSign1 = (GzPartitionsCell{ii}.area < 0 && (dispersionDueToThisPartition >= phaseDispersionZ));
                    haveSameSign2 = (GzPartitionsCell{ii}.area > 0 && (dispersionDueToThisPartition <= phaseDispersionZ));
                    if (haveSameSign1 || haveSameSign2)
                        GzSpoilersCell{ii} = mr.makeTrapezoid('z','Area',AreaSpoilingNeededZ,'Duration',fixedDurationGradient,'system',systemLimits);
                    else
                        GzSpoilersCell{ii} = mr.makeTrapezoid('z','Area',-AreaSpoilingNeededZ,'Duration',fixedDurationGradient,'system',systemLimits);
                    end
                    areaTotal = GzPartitionsCell{ii}.area + GzSpoilersCell{ii}.area;
                    dispersionPerTR(ii) = 2 * pi * partitionThickness * areaTotal;
                end
            end
        end
    end
    
end




