// Approximate the last True Tone white balance while the lid is closed.
// CoreBrightness is a private, runtime-loaded read interface.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <signal.h>
#import <math.h>
@interface NSObject (CB)
-(id)copyPropertyForKey:(id)key andDisplay:(unsigned long long)d;
@end
static volatile sig_atomic_t quitting=0;
static void stop(int s){
    (void)s;
    quitting=1;
}
@interface Sample:NSObject
@property uint32_t count;
@property NSData *r,*g,*b;
@property NSArray *gain;
@property CGDirectDisplayID display;
@end
@implementation Sample
@end
static int lid(void){
    io_service_t s=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("IOPMrootDomain"));
    if(!s)return -1;
    CFTypeRef v=IORegistryEntryCreateCFProperty(s,CFSTR("AppleClamshellState"),kCFAllocatorDefault,0);
    IOObjectRelease(s);
    if(!v)return -1;
    int result=CFGetTypeID(v)==CFBooleanGetTypeID()?CFBooleanGetValue(v):-1;
    CFRelease(v);
    return result;
}
static NSString *key(CGDirectDisplayID d){
    return [NSString stringWithFormat:@"%u-%u-%u-%u",CGDisplayVendorNumber(d),CGDisplayModelNumber(d),CGDisplaySerialNumber(d),d];
}
static Sample *capture(id client,CGDirectDisplayID d){
    NSDictionary*p=[client copyPropertyForKey:@"ColorRamp" andDisplay:d];
    NSArray*m=p[@"ColorRampTarget"];
    if(m.count!=9)return nil;
    float r[4096],g[4096],b[4096];
    uint32_t n=0;
    if(CGGetDisplayTransferByTable(d,4096,r,g,b,&n)!=kCGErrorSuccess||!n)return nil;
    NSMutableArray *gains=[NSMutableArray new];
    for(int i=0;i<3;i++){
        double v=0;
        for(int j=0;j<3;j++)v+=[m[i*3+j] doubleValue];
        if(!isfinite(v)||v<0.2||v>1.5)return nil;
        [gains addObject:@(pow(fmin(v,1.0),1.0/2.2))];
    }
    Sample*s=[Sample new];
    s.count=n;
    s.r=[NSData dataWithBytes:r length:n*sizeof(float)];
    s.g=[NSData dataWithBytes:g length:n*sizeof(float)];
    s.b=[NSData dataWithBytes:b length:n*sizeof(float)];
    s.gain=gains;
    s.display=d;
    return s;
}
static CGError apply(Sample*s,CGDirectDisplayID d,BOOL tint){
    float r[4096],g[4096],b[4096];
    const float*rr=s.r.bytes,*gg=s.g.bytes,*bb=s.b.bytes;
    for(uint32_t i=0;i<s.count;i++){
        r[i]=rr[i]*(tint?[s.gain[0] floatValue]:1);
        g[i]=gg[i]*(tint?[s.gain[1] floatValue]:1);
        b[i]=bb[i]*(tint?[s.gain[2] floatValue]:1);
    }
    return CGSetDisplayTransferByTable(d,s.count,r,g,b);
}
static NSArray *displays(void){
    CGDirectDisplayID ds[32];
    uint32_t n=0;
    NSMutableArray*a=[NSMutableArray new];
    if(CGGetOnlineDisplayList(32,ds,&n)==0)for(uint32_t i=0;i<n;i++)if(!CGDisplayIsBuiltin(ds[i]))[a addObject:@(ds[i])];
    return a;
}
int main(int argc,char**argv){
    @autoreleasepool{
        signal(SIGTERM,stop);
        signal(SIGINT,stop);
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",RTLD_NOW);
        id client=[NSClassFromString(@"BrightnessSystemClient") new];
        if(!client)return 1;
        BOOL test=argc>1&&!strcmp(argv[1],"--self-test");
        NSMutableDictionary<NSString*,Sample*>*samples=[NSMutableDictionary new],*held=[NSMutableDictionary new];
        int last=-1;
        double openedAt=0,closedAt=0;
        NSLog(@"True Tone Hold started; external displays only; lid=%d",lid());
        do{
            @autoreleasepool{
                double now=NSProcessInfo.processInfo.systemUptime;
                int closed=lid();
                NSArray *online=displays();
                if(closed==0){
                    if(last!=0){
                        for(NSNumber*num in online){
                            NSString*k=key(num.unsignedIntValue);
                            Sample*s=k?held[k]:nil;
                            if(s)NSLog(@"Restore %u: %d",num.unsignedIntValue,apply(s,num.unsignedIntValue,NO));
                        }
                        [held removeAllObjects];
                        openedAt=now;
                        NSLog(@"Lid open: native True Tone in control");
                    }
                    if(test||now-openedAt>2){
                        for(NSNumber*num in online){
                            CGDirectDisplayID d=num.unsignedIntValue;
                            NSString*k=key(d);
                            Sample*s=capture(client,d);
                            if(k&&s)samples[k]=s;
                            if(test&&s){
                                NSLog(@"Captured display %u gains=%@",d,s.gain);
                                CGError e=apply(s,d,YES);
                                float r[4096],g[4096],b[4096];
                                uint32_t n=0;
                                CGError re=CGGetDisplayTransferByTable(d,4096,r,g,b,&n);
                                BOOL matches=re==0&&n==s.count&&fabs(b[n-1]-((const float*)s.b.bytes)[n-1]*[s.gain[2] floatValue])<0.002;
                                CGError restore=apply(s,d,NO);
                                NSLog(@"Gamma test write=%d read=%d match=%d restore=%d",e,re,matches,restore);
                                if(e||!matches||restore)return 2;
                            }
                        }
                    }
                }
                else if(closed==1){
                    if(last!=1){
                        closedAt=now;
                        NSLog(@"Lid closed: freezing last measured warmth");
                    }
                    if(now-closedAt>=1){
                        for(NSNumber*num in online){
                            CGDirectDisplayID d=num.unsignedIntValue;
                            NSString*k=key(d);
                            Sample*s=k?samples[k]:nil;
                            if(!s)continue;
                            CGError e=apply(s,d,YES);
                            if(!held[k])NSLog(@"Hold %u gains=%@ result=%d",d,s.gain,e);
                            if(e==0)held[k]=s;
                        }
                    }
                }
                last=closed;
                if(test){
                    if(samples.count==0){
                        NSLog(@"No sample captured; open lid required");
                        return 3;
                    }
                    return 0;
                }
            }
        }
        while(!quitting && (usleep(500000),1));
        for(NSNumber*num in displays()){
            NSString*k=key(num.unsignedIntValue);
            Sample*s=k?held[k]:nil;
            if(s)apply(s,num.unsignedIntValue,NO);
        }
        NSLog(@"Stopped and restored display gamma");
    }
    return 0;
}
