import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsOptional, Max, Min } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';
import {
  AiProviderEnum,
  EngineProviderEnum,
  LanguageEnum,
  SideToMoveEnum,
} from './analyze-board.dto';

/**
 * Multipart form fields for POST /api/analysis/screenshot. The image file
 * itself is handled separately by Multer; these are the accompanying text
 * fields. @Type(() => Number) coerces numeric strings that arrive via
 * multipart so class-validator's @IsInt checks pass.
 */
export class AnalyzeScreenshotDto {
  @ApiProperty({ required: false, enum: AiProviderEnum })
  @IsOptional()
  @IsEnum(AiProviderEnum)
  provider?: AiProviderEnum;

  @ApiProperty({ required: false, enum: SideToMoveEnum })
  @IsOptional()
  @IsEnum(SideToMoveEnum)
  sideToMove?: SideToMoveEnum;

  @ApiProperty({ required: false, enum: EngineProviderEnum })
  @IsOptional()
  @IsEnum(EngineProviderEnum)
  engineProvider?: EngineProviderEnum;

  @ApiProperty({ required: false, minimum: 1, maximum: 30 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(30)
  engineDepth?: number;

  @ApiProperty({ required: false, minimum: 50, maximum: 60000 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(50)
  @Max(60000)
  engineMoveTimeMs?: number;

  @ApiProperty({ required: false, minimum: 1, maximum: 1024, description: 'Pikafish Threads.' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(1024)
  engineThreads?: number;

  @ApiProperty({ required: false, minimum: 1, maximum: 32768, description: 'Pikafish Hash (MB).' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(32768)
  engineHashMb?: number;

  @ApiProperty({ required: false, minimum: 1, maximum: 10, description: 'Top-N moves (MultiPV).' })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(10)
  engineMultiPv?: number;

  @ApiProperty({ required: false, enum: LanguageEnum, description: 'Move-notation language.' })
  @IsOptional()
  @IsEnum(LanguageEnum)
  language?: LanguageEnum;
}
