import 'package:flutter/material.dart';
import '../utils/constants.dart';

class AppLogo extends StatelessWidget {
  final double? width;
  final double? height;
  final bool isFullLogo;

  const AppLogo._({
    this.width,
    this.height,
    required this.isFullLogo,
  });

  factory AppLogo.full({double? width, double? height}) {
    return AppLogo._(
      width: width,
      height: height,
      isFullLogo: true,
    );
  }

  factory AppLogo.icon({double? width, double? height}) {
    return AppLogo._(
      width: width ?? 80,
      height: height ?? 80,
      isFullLogo: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = isFullLogo
        ? AppConstants.logoFullVertical
        : AppConstants.logoIcon;

    return Image.asset(
      imagePath,
      width: width,
      height: height,
      fit: BoxFit.contain,
    );
  }
}
