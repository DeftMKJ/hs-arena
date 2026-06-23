#import "OpenCVDraftImageMatcher.h"

#import <opencv2/opencv.hpp>

static cv::Mat MatFromUIImage(UIImage *image);
static double HSVDistance(const cv::Mat &firstMat, const cv::Mat &secondMat);
static cv::Mat HSVHistogram(const cv::Mat &bgrMat);
static double ORBDistance(const cv::Mat &firstMat, const cv::Mat &secondMat);

@implementation OpenCVDraftImageMatcher

+ (double)hsvDistanceBetweenImage:(UIImage *)firstImage
                       secondImage:(UIImage *)secondImage {
    cv::Mat firstMat = MatFromUIImage(firstImage);
    cv::Mat secondMat = MatFromUIImage(secondImage);
    if (firstMat.empty() || secondMat.empty()) {
        return DBL_MAX;
    }

    cv::Mat firstHist = HSVHistogram(firstMat);
    cv::Mat secondHist = HSVHistogram(secondMat);
    if (firstHist.empty() || secondHist.empty()) {
        return DBL_MAX;
    }

    return cv::compareHist(firstHist, secondHist, cv::HISTCMP_BHATTACHARYYA);
}

+ (double)combinedDistanceBetweenImage:(UIImage *)firstImage
                            secondImage:(UIImage *)secondImage {
    cv::Mat firstMat = MatFromUIImage(firstImage);
    cv::Mat secondMat = MatFromUIImage(secondImage);
    if (firstMat.empty() || secondMat.empty()) {
        return DBL_MAX;
    }

    double hsvDistance = HSVDistance(firstMat, secondMat);
    double orbDistance = ORBDistance(firstMat, secondMat);
    if (hsvDistance == DBL_MAX && orbDistance == DBL_MAX) {
        return DBL_MAX;
    }
    if (orbDistance == DBL_MAX) {
        return hsvDistance;
    }
    if (hsvDistance == DBL_MAX) {
        return orbDistance;
    }

    return hsvDistance * 0.35 + orbDistance * 0.65;
}

static cv::Mat MatFromUIImage(UIImage *image) {
    CGImageRef imageRef = image.CGImage;
    if (imageRef == nil) {
        return cv::Mat();
    }

    const size_t width = CGImageGetWidth(imageRef);
    const size_t height = CGImageGetHeight(imageRef);
    if (width == 0 || height == 0) {
        return cv::Mat();
    }

    cv::Mat rgbaMat((int)height, (int)width, CV_8UC4);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        rgbaMat.data,
        width,
        height,
        8,
        rgbaMat.step[0],
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault
    );
    CGColorSpaceRelease(colorSpace);

    if (context == nil) {
        return cv::Mat();
    }

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
    CGContextRelease(context);

    cv::Mat bgrMat;
    cv::cvtColor(rgbaMat, bgrMat, cv::COLOR_RGBA2BGR);
    return bgrMat;
}

static double HSVDistance(const cv::Mat &firstMat, const cv::Mat &secondMat) {
    cv::Mat firstHist = HSVHistogram(firstMat);
    cv::Mat secondHist = HSVHistogram(secondMat);
    if (firstHist.empty() || secondHist.empty()) {
        return DBL_MAX;
    }
    return cv::compareHist(firstHist, secondHist, cv::HISTCMP_BHATTACHARYYA);
}

static cv::Mat HSVHistogram(const cv::Mat &bgrMat) {
    cv::Mat hsvMat;
    cv::cvtColor(bgrMat, hsvMat, cv::COLOR_BGR2HSV);

    int histSize[] = {50, 60};
    float hueRange[] = {0, 180};
    float saturationRange[] = {0, 256};
    const float *ranges[] = {hueRange, saturationRange};
    int channels[] = {0, 1};

    cv::Mat hist;
    cv::calcHist(&hsvMat, 1, channels, cv::Mat(), hist, 2, histSize, ranges, true, false);
    cv::normalize(hist, hist, 0, 1, cv::NORM_MINMAX, -1, cv::Mat());
    return hist;
}

static double ORBDistance(const cv::Mat &firstMat, const cv::Mat &secondMat) {
    cv::Mat firstGray;
    cv::Mat secondGray;
    cv::cvtColor(firstMat, firstGray, cv::COLOR_BGR2GRAY);
    cv::cvtColor(secondMat, secondGray, cv::COLOR_BGR2GRAY);
    cv::resize(firstGray, firstGray, cv::Size(160, 160));
    cv::resize(secondGray, secondGray, cv::Size(160, 160));

    cv::Ptr<cv::ORB> orb = cv::ORB::create(500);
    std::vector<cv::KeyPoint> firstKeypoints;
    std::vector<cv::KeyPoint> secondKeypoints;
    cv::Mat firstDescriptors;
    cv::Mat secondDescriptors;
    orb->detectAndCompute(firstGray, cv::noArray(), firstKeypoints, firstDescriptors);
    orb->detectAndCompute(secondGray, cv::noArray(), secondKeypoints, secondDescriptors);
    if (firstDescriptors.empty() || secondDescriptors.empty() || firstKeypoints.empty() || secondKeypoints.empty()) {
        return DBL_MAX;
    }

    cv::BFMatcher matcher(cv::NORM_HAMMING);
    std::vector<std::vector<cv::DMatch>> knnMatches;
    matcher.knnMatch(firstDescriptors, secondDescriptors, knnMatches, 2);

    std::vector<cv::DMatch> goodMatches;
    for (const std::vector<cv::DMatch> &matches : knnMatches) {
        if (matches.size() < 2) {
            continue;
        }
        if (matches[0].distance < 0.78f * matches[1].distance) {
            goodMatches.push_back(matches[0]);
        }
    }

    if (goodMatches.empty()) {
        return 1.0;
    }

    double averageDistance = 0;
    for (const cv::DMatch &match : goodMatches) {
        averageDistance += match.distance;
    }
    averageDistance /= (double)goodMatches.size();

    double keypointBase = std::max(1.0, (double)std::min(firstKeypoints.size(), secondKeypoints.size()));
    double matchRatio = std::min(1.0, (double)goodMatches.size() / keypointBase);
    double normalizedDescriptorDistance = std::min(1.0, averageDistance / 80.0);

    return std::max(0.0, std::min(1.0, normalizedDescriptorDistance * 0.55 + (1.0 - matchRatio) * 0.45));
}

@end
