function [Xsol, infos, sub_infos, Xinit] = petrels_mod(Xinit, A_in, Omega_in, Gamma_in, numr, numc, options)
% Interface file for Petrels algorithm
%
% Inputs:
%       A_in            full tensor data to be tracked.
%       Omega_in        logical data of traing tensor set to speficy observable/missing elements.
%       Gamma_in        logical data of test tensor set to speficy observable/missing elements.
%       tensor_dims     dimension of tensor.
%       rank            max rank.
%       xinit           initial tensor data.
%       options         structure data of options.
% Output:
%       XSol            solution.
%       infos           information.
%       sub_infos       sub information.
%
%                   
% This file is part of OLSTEC package.
%
% Created by H.Kasai on June 07, 2017


    A               = A_in;
    Omega           = Omega_in;
    Gamma           = Gamma_in;
    
    maxepochs           = options.maxepochs;
    maxrank             = options.rank;
    verbose             = options.verbose;
    tolcost             = options.tolcost;
    store_subinfo       = options.store_subinfo;      
    store_matrix        = options.store_matrix; 
    lambda              = options.lambda; 
    
    if ~isfield(options, 'permute_on')
        permute_on = 1;
    else
        permute_on = options.permute_on;
    end      
    

    if isempty(Xinit)
        % initialize U to a random r-dimensional subspace 
        %U = orth(randn(numr,maxrank)); 
        %Xinit = U;
        U = randn(numr, maxrank);
        Weight = randn(maxrank, numc);
    else
        U = Xinit.U;
        Weight = Xinit.Weight;
    end


    % calculate initial cost
    Rec = U * Weight;
    train_cost = compute_cost_matrix(Rec, Omega, A);
    if ~isempty(Gamma)
        test_cost = compute_cost_matrix(Rec, Gamma, A);
    else
        test_cost = 0;
    end  
  
    % initialize infos
    infos.iter = 1;
    infos.train_cost = train_cost;
    infos.test_cost = test_cost;
    infos.time = 0;    

    % initialize sub_infos
    sub_infos.inner_iter = [];
    sub_infos.err_residual = [];
    sub_infos.err_run_ave = []; 
    sub_infos.global_train_cost = []; 
    sub_infos.global_test_cost = [];  
    if store_matrix
        sub_infos.I = zeros(numr, numc);
        sub_infos.L = zeros(numr, numc);
        sub_infos.E = zeros(numr, numc);
    end      
    
    % prepare buffer
    Rinv    = repmat(100*eye(maxrank),1,numr);

    % main loop
    for outiter = 1 : maxepochs
        
        % permute samples
        if permute_on
            col_order = randperm(numc);
        else
            col_order = 1:numc;
        end         

        % Begin the time counter for the epoch
        t_begin = tic();    

        for k= 1 : numc
            
            % Pull out the relevant indices and revealed entries for this column
            I = A(:,col_order(k));
            idx = find(Omega(:,col_order(k))>0);
            I_Omega = I(idx);

            v_Omega = I_Omega;
            U_Omega = U(idx,:);    

            % Predict the best approximation of v_Omega by u_Omega.  
            % That is, find weights to minimize ||U_Omega*weights-v_Omega||^2
            weights = pinv(U_Omega)*v_Omega;
            norm_weights = norm(weights);

            % Compute the residual not predicted by the current estmate of U.
            residual = v_Omega - U_Omega*weights;       

            % This step update Rinv matrix with forgetting parameter lambda
            % for each observed row in U
            %lambda = 1-0.02*exp(-0.001*((outiter-1)*TOTAL_SLICE+k-1));

            % parallel update
            for i=1:length(idx)

                Tinv = Rinv(:,(idx(i)-1)*maxrank+1:idx(i)*maxrank);
                ss = Tinv*weights;
                Tinv = (Tinv-ss*ss'*1/(lambda+weights'*Tinv*weights));

                % update U_omega
                U(idx(i),:) = U_Omega(i,:) + lambda^(-1)*residual(i)*weights'*Tinv;

                Rinv(:,(idx(i)-1)*maxrank+1:idx(i)*maxrank) = Tinv;
            end

            Rinv = lambda^(-1)*Rinv;

            % Reculculate weights
            weights = pinv(U_Omega)*v_Omega;
            Weight(:, col_order(k)) = weights;


            % Reconstruct Low-maxrank Matrix
            L_rec = U * weights; 
            
            % Store reconstruction error
            if store_matrix
                E_rec = I - L_rec;
                complete_idx = zeros(numr, 1);
                complete_idx(idx) = 1;
                sub_infos.I(:,k) = I .* complete_idx;
                sub_infos.L(:,k) = L_rec;
                sub_infos.E(:,k) = E_rec;
            end            

            
            if store_subinfo
                % Frame-unit Estimation Error
                norm_residual   = norm(I(:) - L_rec(:));
                norm_A_Slice    = norm(I(:));
                error           = norm_residual/norm_A_Slice; 
                sub_infos.inner_iter    = [sub_infos.inner_iter (outiter-1)*numc + k];
                sub_infos.err_residual  = [sub_infos.err_residual error];  

                % Running-average Estimation Error
                if k == 1
                    run_error   = error;
                else
                    run_error   = (sub_infos.err_run_ave(end) * (k-1) + error)/k;
                end
                sub_infos.err_run_ave     = [sub_infos.err_run_ave run_error];            

                % Global train_cost computation
                Rec = U * Weight;    
                train_cost = compute_cost_matrix(Rec, Omega, A);
                if ~isempty(Gamma)
                    test_cost = compute_cost_matrix(Rec, Gamma, A);
                else
                    test_cost = 0;
                end                 
                sub_infos.global_train_cost  = [sub_infos.global_train_cost train_cost]; 
                sub_infos.global_test_cost  = [sub_infos.global_test_cost test_cost]; 
                
                if verbose > 1
                    fprintf('Petrels: fnum = %03d, cost = %e, error = %e\n', k+(outiter-1)*numc, train_cost, error);
                end                 
            end
          
        end

                
        % store infos
        infos.iter = [infos.iter; outiter];
        infos.time = [infos.time; infos.time(end) + toc(t_begin)];        
        
        if ~store_subinfo
            Rec = U * Weight;
            train_cost = compute_cost_matrix(Rec, Omega, A);
            if ~isempty(Gamma)
                test_cost = compute_cost_matrix(Rec, Gamma, A);
            else
                test_cost = 0;
            end            
        end
        infos.train_cost = [infos.train_cost; train_cost];
        infos.test_cost = [infos.test_cost; test_cost]; 
        
        
        if verbose > 1
            fprintf('Petrels: Epoch %0.3d, Cost %7.3e\n', outiter, train_cost);
        end
        
        % stopping criteria: cost tolerance reached
        if train_cost < tolcost
            fprintf('train_cost sufficiently decreased.\n');
            break;
        end        
    end




% Once we have settled on our column space, a single pass over the data
% suffices to compute the weights associated with each column.  You only
% need to compute these weights if you want to make predictions about these
% columns.
% fprintf('Find column weights...');
% R = zeros(numc,maxrank);
% for k=1:numc,     
%     % Pull out the relevant indices and revealed entries for this column
%     idx = find(Indicator(:,k));
%     v_Omega = values(idx,k);
%     U_Omega = U(idx,:);
%     % solve a simple least squares problem to populate R
%     R(k,:) = (U_Omega\v_Omega)';
% end

    Xsol.U = U;
    Xsol.Weight = weights;

end



