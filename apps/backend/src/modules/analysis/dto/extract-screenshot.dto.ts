import { IsEnum, IsOptional } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import { AiProviderEnum, SideToMoveEnum } from './analyze-board.dto';

/**
 * Multipart form fields for POST /api/analysis/extract (vision-only). No engine
 * options or notation language — extraction returns the board, not a move.
 */
export class ExtractScreenshotDto {
  @ApiProperty({ required: false, enum: AiProviderEnum })
  @IsOptional()
  @IsEnum(AiProviderEnum)
  provider?: AiProviderEnum;

  @ApiProperty({ required: false, enum: SideToMoveEnum })
  @IsOptional()
  @IsEnum(SideToMoveEnum)
  sideToMove?: SideToMoveEnum;
}
