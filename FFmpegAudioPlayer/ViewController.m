//
//  ViewController.m
//  FFmpegAudioPlayer
//
//  Created by Liao KuoHsun on 13/4/19.
//  Copyright (c) 2013年 Liao KuoHsun. All rights reserved.
//

#import "ViewController.h"
#import "AudioPlayer.h"

#define WAV_FILE_NAME @"1.wav"

// If we read too fast, the size of aqQueue will increased quickly.
// If we read too slow, .
#define LOCAL_FILE_DELAY_MS 80  


// Reference for AAC test file
// http://download.wavetlan.com/SVV/Media/HTTP/http-aac.htm
// http://download.wavetlan.com/SVV/Media/RTSP/darwin-aac.htm


// Test local file
#define AUDIO_TEST_PATH @"AAC_12khz_Mono_5.aac"

// Test remote file
//#define AUDIO_TEST_PATH @"rtsp://216.16.231.19/BlackBerry.mp4"
//#define AUDIO_TEST_PATH @"rtsp://mm2.pcslab.com/mm/7h800.mp4"
//#define AUDIO_TEST_PATH @"rtsp://216.16.231.19/The_Simpsons_S19E05_Treehouse_of_Horror_XVIII.3GP"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    return;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    NSLog(@"didReceiveMemoryWarning");
}

- (IBAction)PlayAudio:(id)sender {
    
    UIButton *vBn = (UIButton *)sender;
    UIAlertView *pLoadRtspAlertView;
    UIActivityIndicatorView *pIndicator;
    
    if([vBn.currentTitle isEqualToString:@"Stop"])
    {
        pLoadRtspAlertView = nil;
        pIndicator = nil;
        
        [self destroyFFmpegAudioStream];            
        [aPlayer Stop:FALSE];        
        [apQueue destroyQueue];
        apQueue = nil;
        [vBn setTitle:@"Play" forState:UIControlStateNormal];
        return;
    }
    else
    {
        [vBn setTitle:@"Stop" forState:UIControlStateNormal];
    }
    
    pLoadRtspAlertView = [[UIAlertView alloc] initWithTitle:@"\n\nConnecting\nPlease Wait..."
                                        message:nil delegate:self cancelButtonTitle:nil otherButtonTitles: nil];
    [pLoadRtspAlertView show];
    pIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    
    // Adjust the indicator so it is up a few pixels from the bottom of the alert
    pIndicator.center = CGPointMake(pLoadRtspAlertView.bounds.size.width / 2, pLoadRtspAlertView.bounds.size.height - 50);
    [pIndicator startAnimating];
    [pLoadRtspAlertView addSubview:pIndicator];

    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        if([self initFFmpegAudioStream]==FALSE){
            NSLog(@"initFFmpegAudio fail");
            return;
        }
        
        apQueue = [[AudioPacketQueue alloc]initQueue];
        aPlayer = [[AudioPlayer alloc]initAudio:apQueue withCodecCtx:(AVCodecContext *) pAudioCodecCtx];

        // Dismiss alertview in main thread
        // Run Audio Player in main thread
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            [pIndicator stopAnimating];
            [pLoadRtspAlertView dismissWithClickedButtonIndex:0 animated:YES];
            [self initiOSAudio:nil];
            
        });

//        [self performSelectorOnMainThread:@selector(initiOSAudio:) withObject:nil waitUntilDone:YES];
        
        // Read ffmpeg audio packet in another thread
        [self readFFmpegAudioFrameAndDecode];

    });
}

-(void) initiOSAudio:(id) sender {
    // wait, so that packet queue will buffer audio data for playing
    sleep(2);
    
    if([aPlayer getStatus]!=eAudioRunning)
    {
        [aPlayer Play];
    }
}


-(BOOL) initFFmpegAudioStream{
    
    NSString *pAudioInPath;
    AVCodec  *pAudioCodec;
    
    if( strncmp([AUDIO_TEST_PATH UTF8String], "rtsp", 4)==0)
    {
        pAudioInPath = AUDIO_TEST_PATH;
        IsLocalFile = FALSE;
    }
    else
    {
        pAudioInPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:AUDIO_TEST_PATH];
        IsLocalFile = TRUE;
    }
        
    avcodec_register_all();
    av_register_all();
    if(IsLocalFile!=TRUE)
    {
        avformat_network_init();
    }
    
    pFormatCtx = avformat_alloc_context();
    AVDictionary *opts = 0;
    av_dict_set(&opts, "rtsp_transport", "tcp", 0);
    NSLog(@"%@", pAudioInPath);
    
    // Open video file
    if(avformat_open_input(&pFormatCtx, [pAudioInPath cStringUsingEncoding:NSASCIIStringEncoding], NULL, &opts) != 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't open file\n");
        return FALSE;
    }
	av_dict_free(&opts);
    pAudioInPath = nil;
    
    // Retrieve stream information
    if(avformat_find_stream_info(pFormatCtx,NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't find stream information\n");
        return FALSE;
    }
    
    // Dumpt stream information
    av_dump_format(pFormatCtx, 0, [pAudioInPath UTF8String], 0);
    
    
    // 20130329 albert.liao modified start
    // Find the first video stream
    if ((audioStream =  av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, &pAudioCodec, 0)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find a audio stream in the input file\n");
        return FALSE;
    }
	
    if(audioStream>=0){
        
        NSLog(@"== Audio pCodec Information");
        NSLog(@"name = %s",pAudioCodec->name);
        NSLog(@"sample_fmts = %d",*(pAudioCodec->sample_fmts));
        if(pAudioCodec->profiles)
            NSLog(@"profiles = %s",pAudioCodec->name);
        else
            NSLog(@"profiles = NULL");
        
        // Get a pointer to the codec context for the video stream
        pAudioCodecCtx = pFormatCtx->streams[audioStream]->codec;
        
        // Find the decoder for the video stream
        pAudioCodec = avcodec_find_decoder(pAudioCodecCtx->codec_id);
        if(pAudioCodec == NULL) {
            av_log(NULL, AV_LOG_ERROR, "Unsupported audio codec!\n");
            return FALSE;
        }
        
        // Open codec
        if(avcodec_open2(pAudioCodecCtx, pAudioCodec, NULL) < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot open audio decoder\n");
            return FALSE;
        }
    }
    
    return TRUE;
}


-(void) destroyFFmpegAudioStream{
    IsStop = TRUE;
    avformat_network_deinit();
    if (pAudioCodecCtx)
        avcodec_close(pAudioCodecCtx);
    if (pFormatCtx)
        avformat_close_input(&pFormatCtx);
}


-(void)readFFmpegAudioFrameAndDecode {
    int vErr;
    AVPacket vxPacket;
    av_init_packet(&vxPacket);    
    
    if(IsLocalFile == TRUE)
    {
        while(!IsStop)
        {
            vErr = av_read_frame(pFormatCtx, &vxPacket);
            if(vErr>=0)
            {
                if(vxPacket.stream_index==audioStream) {
                    int ret = [apQueue putAVPacket:&vxPacket];
                    if(ret <= 0)
                        NSLog(@"Put Audio Packet Error!!");
                    
                    // TODO: use pts/dts to decide the delay time 
                    usleep(1000*LOCAL_FILE_DELAY_MS);
                    
//                    if(packet.pts != AV_NOPTS_VALUE)
//                    {
//                        audioClock = av_q2d(pAudioCodecCtx->time_base)*packet.dts;
//                    }
                }
                else
                {
                    NSLog(@"receive unexpected packet!!");
                    av_free_packet(&vxPacket);
                }
            }
            else
            {
                NSLog(@"av_read_frame error %d", vErr);
                break;
            }
//            @synchronized(self){
//                av_free_packet(&packet);
//            };
        }
        NSLog(@"Leave ReadFrame");
    }
    else
    {
        while(!IsStop)
        {
            //vxPacket
            vErr = av_read_frame(pFormatCtx, &vxPacket);
            if(vErr>=0)
            {
                if(vxPacket.stream_index==audioStream) {
                    int ret = [apQueue putAVPacket:&vxPacket];
                    if(ret <= 0)
                        NSLog(@"Put Audio Packet Error!!");
                }
                else
                {
                    NSLog(@"receive unexpected packet!!");
                    av_free_packet(&vxPacket);
                }
            }
            else
            {
                NSLog(@"av_read_frame error %d", vErr);
            }
        }
        NSLog(@"Leave ReadFrame");
    }
}


- (IBAction)SaveAsWave:(id)sender {
//    NSString *pAudioInPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:AUDIO_TEST_PATH];
//    NSString *pAudioOutPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:WAV_FILE_NAME];
//    
//    AudioPlayer *Player = [[AudioPlayer alloc]initForDecodeAudioFile:pAudioInPath ToPCMFile:pAudioOutPath];
//    NSLog(@"Save wave file to %@", pAudioOutPath);
}
@end
