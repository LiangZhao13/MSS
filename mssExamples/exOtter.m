% exOtter is compatible with MATLAB and GNU Octave (www.octave.org).
% This script simulates the Maritime Robotics Otter Uncrewed Surface 
% Vehicle (USV), which is controlled by two propellers. SOG, COG, and 
% course rate are estimated using an EKF, and the course autopilot is 
% utilizing a PID pole-placement algorithm.
%
% Author:    Thor I. Fossen
% Date:      2019-07-18
% Revisions: 
%   2021-05-25 Added EKF for COG/SOG/course rate and course autopilot

clearvars;
clear EKF_5states   % Clear persistent states in EKF_5states.m

%% Simulation data
fHz = 50;
h  = 1/fHz;         % Sampling time [s]
Z = 10;             % GNSS measurement frequency (10 times slower)
N  = 2000;		    % Number of samples

% Initial values for x = [ u v w p q r x y z phi theta psi ]'
x = zeros(12,1); x(1) = 1;	   

% EKF covariance matrices and initial states
Qd = 500 * diag([ 1000 1000 ]);
Rd = 0.00000001 * diag([ 1 1 ]);
x_hat = zeros(5,1);

% PID course autopilot (Nomoto gains)
T = 1;
m = 41.4;        % m = T/K
K = T / m;

wn = 1.5;        % Pole-placement parameters
zeta = 1;

Kp = m * wn^2;
Kd = m * (2*zeta*wn - 1/T);
Td = Kd/Kp; 
Ti = 10/wn;

B = 0.0111 * [1 1                   % Input matrix
              0.395 -0.395 ];
Binv = inv(B);

z = 0;                              % Integral state

% Reference model specifying the closed-loop dynamics
wn_d = 0.5;         % Desired natural frequency
zeta_d = 1.0;       % Desired relative damping factor

chi_d = 0;
omega_d = 0;
a_d = 0;

% Propeller dynamics
Tn = 1;                % Propeller time constant      
n = [0 0]';            % n = [ n_left n_right ]'

% Load condition
mp = 25;               % Payload mass (kg), max value 45 kg
rp = [0 0 -0.35]';     % Location of payload (m)

% Ocean current
V_c = 0;               % Current speed (m/s)
beta_c = 30 * pi/180;  % Current direction (rad)

%% MAIN LOOP
simdata = zeros(N+1,20);                   % Table for simulation data

for i=1:N+1
   t = (i-1) * h;                          % Time (s)   
   
   % Course angle setpoints
   if ( t < 20 )
       chi_ref = 20 * pi / 180;
   else
       chi_ref = 0 * pi / 180; 
   end
   
   % Course autopilot (PID pole placement with reference model)
   tau_X = 100;
   tau_N = (T/K) * a_d + (1/K) * omega_d -... 
        Kp * ( ssa( x_hat(4)-chi_d ) +...
        Td * (x_hat(5) - omega_d) + (1/Ti) * z );
   u = Binv * [tau_X tau_N]';
   n_c = sign(u) .* sqrt( abs(u) );   
   
   % n_c = [80 60]';          % n = [ n_left n_right ]' 
   
   % Reference model jerk
   j_d = wn_d^3 * ssa(chi_ref - chi_d) - (2*zeta_d+1) * wn_d^2 * omega_d...
       - (2*zeta_d+1) * wn_d * a_d;
   
   % Store simulation data in a table   
   simdata(i,:) = [t x' x_hat' n'];    
   
   % 5-state EKF:  x_hat[k+1] = [x_N, v_N, U, chi, omega]'
   x_N = x(7); y_E = x(8);      % GNSS measurements
   x_hat = EKF_5states(x_N,y_E,h,Z,'NED',Qd,Rd);  
      
   % Euler's method (k+1)
   x = x + h * otter(x,n,mp,rp,V_c,beta_c);
   z = z + h * ssa( x_hat(4)-chi_d );
   n = n - h/Tn * (n - n_c);  
   chi_d = chi_d + h * omega_d;  
   omega_d = omega_d + h * a_d;
   a_d = a_d + h * j_d;   
end

%% PLOTS
t    = simdata(:,1); 
nu   = simdata(:,2:7); 
eta  = simdata(:,8:13); 

u = nu(:,1);
v = nu(:,2);
U = sqrt(u.^2 + v.^2);           % Speed
psi = eta(:,6);                  % Heading angle
beta_c = ssa( atan2(v,u) );      % Crab angle
chi = psi + beta_c;              % Course angle

x_hat = simdata(:,14);
y_hat = simdata(:,15);
U_hat = simdata(:,16);
chi_hat = simdata(:,17);
omega_hat = simdata(:,18);

n1 = simdata(:,19);
n2 = simdata(:,20);

clf
figure(1)
subplot(611),plot(t,nu(:,1))
xlabel('time (s)'),title('Surge velocity (m/s)'),legend('True'),grid
subplot(612),plot(t,nu(:,2))
xlabel('time (s)'),title('Sway velocity (m/s)'),legend('True'),grid
subplot(613),plot(t,nu(:,3))
xlabel('time (s)'),title('Heave velocity (m/s)'),legend('True'),grid
subplot(614),plot(t,(180/pi)*nu(:,4))
xlabel('time (s)'),title('Roll rate (deg/s)'),legend('True'),grid
subplot(615),plot(t,(180/pi)*nu(:,5))
xlabel('time (s)'),title('Pitch rate (deg/s)'),legend('True'),grid
subplot(616),plot(t,(180/pi)*nu(:,6))
xlabel('time (s)'),title('Yaw rate (deg/s)'),legend('True'),grid
set(findall(gcf,'type','text'),'FontSize',14)
set(findall(gcf,'type','legend'),'FontSize',14)
set(findall(gcf,'type','line'),'linewidth',2)

figure(2)
subplot(611),plot(eta(:,2),eta(:,1),y_hat,x_hat); 
title('xy plot (m)'),legend('True','Estimate'),grid
subplot(612),plot(t,U,t,U_hat);
xlabel('time (s)'),title('speed (m/s)'),legend('True','Estimate'),grid
subplot(613),plot(t,eta(:,3))
xlabel('time (s)'),title('heave z position (m)'),legend('True'),grid
subplot(614),plot(t,(180/pi)*eta(:,4))
xlabel('time (s)'),title('roll angle (deg)'),legend('True'),grid
subplot(615),plot(t,(180/pi)*eta(:,5))
xlabel('time (s)'),title('pitch angle (deg)'),legend('True'),grid
subplot(616),plot(t,(180/pi)*psi)
xlabel('time (s)'),title('yaw angle (deg)'),
legend('True'),grid
set(findall(gcf,'type','text'),'FontSize',14)
set(findall(gcf,'type','legend'),'FontSize',14)
set(findall(gcf,'type','line'),'linewidth',2)

figure(3)
subplot(311),plot(t,(180/pi)*chi,t,(180/pi)*chi_hat)
xlabel('time (s)'),title('course angle (deg)')
legend('True','Estimate'),grid
subplot(312),plot(t,(180/pi)*omega_hat,'r')
xlabel('time (s)'),title('course rate (deg(/s)')
legend('Estimate'),grid
subplot(313),plot(t,n1,'g',t,n2,'k'),grid
xlabel('time (s)')
legend('n_1 left propeller','n_2 right propeller')
title('Propeller revolutions (rad/s)')
set(findall(gcf,'type','text'),'FontSize',14)
set(findall(gcf,'type','legend'),'FontSize',14)
set(findall(gcf,'type','line'),'linewidth',2)
