#import "TPProgressHUD.h"

@interface TPProgressHUD ()
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *stepLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation TPProgressHUD

+ (instancetype)showInView:(UIView *)view title:(NSString *)title {
    TPProgressHUD *hud = [[TPProgressHUD alloc] initWithFrame:view.bounds];
    hud.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    hud.titleLabel.text = title;
    [view addSubview:hud];
    return hud;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];

        _card = [[UIView alloc] init];
        _card.backgroundColor = [UIColor systemBackgroundColor];
        _card.layer.cornerRadius = 14;
        _card.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_card];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont boldSystemFontOfSize:16];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_card addSubview:_titleLabel];

        _stepLabel = [[UILabel alloc] init];
        _stepLabel.font = [UIFont systemFontOfSize:13];
        _stepLabel.textColor = [UIColor secondaryLabelColor];
        _stepLabel.textAlignment = NSTextAlignmentCenter;
        _stepLabel.numberOfLines = 2;
        _stepLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_card addSubview:_stepLabel];

        _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _progressView.translatesAutoresizingMaskIntoConstraints = NO;
        [_card addSubview:_progressView];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        _spinner.translatesAutoresizingMaskIntoConstraints = NO;
        _spinner.hidesWhenStopped = YES;
        [_card addSubview:_spinner];

        [NSLayoutConstraint activateConstraints:@[
            [_card.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_card.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_card.widthAnchor constraintEqualToConstant:270],
            [_titleLabel.topAnchor constraintEqualToAnchor:_card.topAnchor constant:18],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:16],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-16],
            [_stepLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:8],
            [_stepLabel.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:16],
            [_stepLabel.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-16],
            [_progressView.topAnchor constraintEqualToAnchor:_stepLabel.bottomAnchor constant:14],
            [_progressView.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor constant:20],
            [_progressView.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor constant:-20],
            [_progressView.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor constant:-18],
            [_spinner.centerXAnchor constraintEqualToAnchor:_progressView.centerXAnchor],
            [_spinner.centerYAnchor constraintEqualToAnchor:_progressView.centerYAnchor],
        ]];
        _spinner.hidden = YES;
    }
    return self;
}

- (void)updateWithStep:(NSString *)step fraction:(float)fraction {
    self.stepLabel.text = step;
    if (fraction < 0) {
        self.progressView.hidden = YES;
        self.spinner.hidden = NO;
        [self.spinner startAnimating];
    } else {
        self.progressView.hidden = NO;
        [self.spinner stopAnimating];
        self.spinner.hidden = YES;
        [self.progressView setProgress:fraction animated:YES];
    }
}

- (void)dismiss {
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

@end
