Place yolov11-playing-cards.tflite here.

Export from YOLOv11 weights:
  yolo export model=yolov11-playing-cards.pt format=tflite imgsz=640

The resulting .tflite file should be named:
  yolov11-playing-cards.tflite

Without this file, CardDetectionService will fall back to mock state detection.
