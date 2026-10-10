extends RefCounted
## Frozen cloud integrator from 6957127, before ray-only empty-space skipping.
const COMMON := """
global uniform sampler3D ei_cv_shape : filter_linear, repeat_enable;
global uniform sampler3D ei_cv_detail : filter_linear, repeat_enable;
global uniform vec4 ei_cv_weather; // coverage, density, type base, type spread
global uniform vec4 ei_cv_storm; // precipitation, closure, ready, reserved
global uniform vec3 ei_cv_phase0;
global uniform vec3 ei_cv_phase1;
global uniform vec3 ei_cv_phase2;
global uniform vec3 ei_cv_phase3;
global uniform vec3 ei_cv_phase4;
global uniform vec3 ei_cv_phase5;
const float CV_BASE=2200.0;
const float CV_TOP=5800.0;
const vec3 CV_LAYERS[6]=vec3[](vec3(.932327,.361615,47000),vec3(.417595,-.908638,19300),vec3(.764842,.644218,73100),vec3(.891568,.452886,1700),vec3(.305817,-.952090,2850),vec3(.621610,.783327,317));
vec3 cv_coord(vec3 p,int layer){
 vec3 l=CV_LAYERS[layer];vec3 phase=ei_cv_phase0;
 if(layer==1){phase=ei_cv_phase1;}else if(layer==2){phase=ei_cv_phase2;}else if(layer==3){phase=ei_cv_phase3;}else if(layer==4){phase=ei_cv_phase4;}else if(layer==5){phase=ei_cv_phase5;}
 return vec3(l.x*p.x-l.y*p.z,l.y*p.x+l.x*p.z,p.y)/l.z+phase;
}
vec2 cv_weather(vec2 xy){
 vec2 n=cv_coord(vec3(xy.x,0,xy.y),2).xy;
 vec2 warp=(vec2(textureLod(ei_cloud_noise,n+vec2(.17,.63),0.0).r,textureLod(ei_cloud_noise,n+vec2(.67,.29),0.0).r)-.5)*9000.0;
 vec3 p=vec3(xy.x+warp.x,0,xy.y+warp.y);
 float a=textureLod(ei_cloud_noise,cv_coord(p,0).xy+vec2(.31,.07),0.0).r;
 float b=textureLod(ei_cloud_noise,cv_coord(p,1).xy+vec2(.73,.49),0.0).r;
 float v=textureLod(ei_cloud_noise,cv_coord(p,1).xy+vec2(.53,.29),0.0).r;
 return vec2(clamp((a*.6+b*.4-.5)*1.6+.5,0.0,1.0),v);
}
float cv_band(float h,float b0,float b1,float t0,float t1){return clamp((h-b0)/(b1-b0),0.0,1.0)*clamp((t1-h)/max(t1-t0,1e-4),0.0,1.0);}
float cv_density(vec3 p,float footprint,out float local_height){
 local_height=0.0;
 if(p.y<CV_BASE || p.y>CV_TOP){return 0.0;}
 float h=(p.y-CV_BASE)/(CV_TOP-CV_BASE);vec2 w=cv_weather(p.xz);
 float type_noise=textureLod(ei_cloud_noise,cv_coord(vec3(p.x,0,p.z),0).xy+vec2(.53,.29),0.0).r;
 float type_=clamp(ei_cv_weather.z+ei_cv_weather.w*(clamp((type_noise-.5)*2.5+.5,0.0,1.0)*2.0-1.0),0.0,1.0);
 float stratus=clamp(1.0-2.0*type_,0.0,1.0),nimbus=clamp(2.0*type_-1.0,0.0,1.0);vec3 weights=vec3(stratus,1.0-stratus-nimbus,nimbus);
 float weather=mix(w.x,.6+.4*w.x,stratus);weather=mix(weather,.6+.4*weather,ei_cv_storm.y);
 float wc=clamp((weather-(1.0-clamp(ei_cv_weather.x*dot(weights,vec3(1.3,1,1.2)),0.0,1.0)))*2.5,0.0,1.0);
 if(wc<=.001){return 0.0;}
 float s_top=.08+.05*w.y,s_bottom=.012*w.y;
 float ps=cv_band(h,s_bottom,s_bottom+.025,s_top*.55,s_top);
 float core=sqrt(wc),cb=.075+.05*w.y+.05*(1.0-core),ct=cb+.03+.60*core*mix(.5,1.0,w.y);
 float pc=smoothstep(cb,cb+.07,h)*(1.0-smoothstep(mix(cb,ct,.55),ct,h));
 float nb=.02+mix(.05,.17,ei_cv_storm.y)*(1.0-w.y)+.04*(1.0-wc),nt=.5+.5*core;
 float pn=cv_band(h,nb,nb+mix(.08,.17,ei_cv_storm.y),mix(nb,nt,.7),nt);
 local_height=dot(weights,vec3(clamp(h/s_top,0.0,1.0),clamp((h-cb)/(ct-cb),0.0,1.0),clamp((h-nb)/(nt-nb),0.0,1.0)));
 float profile=dot(weights,vec3(ps,pc,pn));if(profile<=0.0){return 0.0;}
 float coverage=min(wc*mix(.75,1.0,max(stratus,nimbus)),.93);
 float shape=textureLod(ei_cv_shape,cv_coord(p,3)+vec3(.13,.71,.29),0.0).r*.65+textureLod(ei_cv_shape,cv_coord(p,4)+vec3(.67,.19,.83),0.0).r*.35;
 // Expand the narrow Perlin/Worley range before the cumulus silhouette
 // threshold, otherwise fair banks join into long solid horizontal rolls.
 shape=mix(shape,clamp((shape-.50)*2.3,0.0,1.0),weights.y);
 shape=mix(shape,.7+.3*shape,stratus*.7);
 float density=clamp((shape-(1.0-coverage))/max(coverage,.001),0.0,1.0)*profile;
 float rounded_coverage=coverage*sqrt(profile);
 float rounded=clamp((shape-(1.0-rounded_coverage))/max(rounded_coverage,.001),0.0,1.0)*sqrt(profile);
 density=mix(density,rounded,weights.y);
 float np=coverage*clamp(profile*1.4,0.0,1.0);
 float dn=clamp((shape-(1.0-np))/max(np,.001),0.0,1.0)*sqrt(profile);
 density=mix(density,dn,nimbus*clamp(ei_cv_storm.x+ei_cv_storm.y,0.0,1.0));
 float detail_weight=1.0-smoothstep(317.0/16.0,317.0/4.0,footprint);
 if(detail_weight>0.0 && density>0.0){
 float noise=textureLod(ei_cv_detail,cv_coord(p,5)+vec3(.41,.23,.59),0.0).r;
 float erosion=mix(noise,1.0-noise,clamp(local_height*4.0,0.0,1.0))*(.16+.16*nimbus*(1.0-local_height))*(1.0-local_height*.3)*detail_weight;
 density=clamp((density-erosion)/max(1.0-erosion,.001),0.0,1.0);
 }
 return density*ei_cv_weather.y*dot(weights,vec3(.85,1,1.15+.55*ei_cv_storm.x));
}
float cv_phase(float cosine,float g){return (1.0-g*g)/(4.0*PI*pow(max(1e-4,1.0+g*g-2.0*g*cosine),1.5));}
vec4 cv_march(vec3 origin,vec3 ray,vec3 light,vec3 cloud_ambient,vec3 sunlight,int steps,int light_steps,float jitter){
 if(ei_cloud_state.w<.5 || ei_cv_storm.z<.5 || ray.y<=.015 || origin.y>=CV_TOP){return vec4(0,0,0,1);}
 float begin=max(10.0,(CV_BASE-origin.y)/max(ray.y,.015));
 float end=min((CV_TOP-origin.y)/max(ray.y,.015),60000.0);
 if(end<=begin){return vec4(0,0,0,1);}
 steps=clamp(int(ceil(float(steps)*log(end/begin)/log(3.0))),max(6,steps/3),min(256,steps*4/3));
 float extinction=mix(.022,.035,ei_cv_storm.x);
 float ratio=pow(end/begin,1.0/float(steps)),t=begin*pow(ratio,jitter),segment_begin=begin,transmittance=1.0;vec3 scatter=vec3(0);
 vec3 toward=length(light)>.1?normalize(light):vec3(0,1,0);float cosine=dot(ray,toward);
 for(int i=0;i<256;i++){
 if(i>=steps || transmittance<.01){break;}
 float dt=segment_begin*(ratio-1.0),local_height;vec3 p=origin+ray*t;
 float density=cv_density(p,max(dt*.25,t*.001),local_height)*(1.0-smoothstep(18000.0,56000.0,t));
 if(density>0.0){
 float depth=0.0,light_step=80.0;vec3 lp=p;
 for(int j=0;j<5;j++){if(j>=light_steps){break;}lp+=toward*light_step;float lh;depth+=cv_density(lp,light_step,lh)*light_step;light_step*=1.9;}
 float lighting=0.0,a=1.0,b=1.0,g=1.0;
 for(int k=0;k<3;k++){float phase=mix(cv_phase(cosine,.6*g),cv_phase(cosine,-.2*g),.3)+(k==0?.2*cv_phase(cosine,.85):0.0);lighting+=a*exp(-extinction*depth*b)*phase;a*=.55;b*=.4;g*=.5;}
 float powder=mix(1.0-.7*exp(-.07*(depth+density*60.0)),1.0,clamp(cosine*.5+.5,0.0,1.0)*.6);
 float relief=mix(1.35,.55,clamp(((p.y-CV_BASE)/(CV_TOP-CV_BASE)-.02)/.14,0.0,1.0));
 vec3 fill=cloud_ambient*mix(.32,.7,local_height)*mix(1.0,relief,ei_cv_storm.y);
 vec3 colour=clamp(fill+sunlight*lighting*4.0*PI*powder*.55,vec3(.018,.025,.04),vec3(.96));
 float step_transmittance=exp(-extinction*density*dt);scatter+=transmittance*colour*(1.0-step_transmittance);transmittance*=step_transmittance;
 }t*=ratio;segment_begin*=ratio;
 }
 float fade=smoothstep(.015,mix(.065,.18,ei_cv_storm.y),ray.y);
 return vec4(scatter*fade,mix(1.0,transmittance,fade));
}
vec3 cv_composite(vec3 base,vec4 cloud,vec3 ray,vec3 cloud_ambient,vec3 sunlight){
 // An overcast horizon thins into bounded atmospheric fill instead of a
 // black plane cut against a saturated fair-weather dome. Empty fields
 // preserve the original sky exactly, including reflected directions.
 float haze=ei_cv_storm.y*clamp(ei_cv_weather.y,0.0,1.0)*(1.0-smoothstep(.02,.3,ray.y));
 vec3 storm_horizon=cloud_ambient*.5+sunlight*.08;
 return mix(base*cloud.a+cloud.rgb,storm_horizon,haze*.7);
}
float cv_shadow(vec3 p,vec3 sun){
 if(ei_cloud_state.w<.5 || ei_cv_storm.z<.5 || ei_cloud_state.y<=0.0 || sun.y<.12 || p.y>=CV_TOP){return 1.0;}
 vec3 toward=normalize(sun);float inv_y=1.0/max(toward.y,.18),depth=0.0;
 for(int i=0;i<8;i++){
 float a=float(i)/8.0,b=float(i+1)/8.0,dz=(CV_TOP-CV_BASE)*(b*b-a*a);
 float altitude=CV_BASE+(CV_TOP-CV_BASE)*(a*a+b*b)*.5;
 float local_height;vec3 q=p+toward*max(0.0,altitude-p.y)*inv_y;
 depth+=cv_density(q,dz*inv_y,local_height)*dz*inv_y;
 }
 return 1.0-ei_cloud_state.y*(1.0-exp(-max(0.0,depth)/200.0));
}
"""
